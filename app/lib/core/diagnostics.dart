import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_controller.dart';
import 'i18n.dart';
import 'models.dart';
import 'queue_manager.dart';

enum DiagLevel { ok, warn, error, info }

class DiagItem {
  DiagItem(this.level, this.title, this.detail);
  final DiagLevel level;
  final String title;
  final String detail;
}

/// Diagnóstico de red y audio para resolver incidencias sin técnico:
/// alcance SIP de cada centralita (OPTIONS), NAT visto por la centralita, registro de
/// cada línea, dispositivos de audio y conexión AMI del panel de cola.
class Diagnostics {
  static Future<List<DiagItem>> run() async {
    final app = AppController.I;
    final out = <DiagItem>[];
    final localIps = await _localIps();
    out.add(DiagItem(DiagLevel.info, tr('Este equipo'),
        '${Platform.operatingSystem} · ${localIps.isEmpty ? tr('sin red IPv4') : localIps.join(', ')}'));

    // 1) Cada servidor distinto: ¿responde a SIP?
    final servers = <String, SipAccountConfig>{};
    for (final l in app.lines.lines) {
      final a = l.account;
      if (a.enabled && a.server.isNotEmpty) servers['${a.server}:${a.port}'] = a;
    }
    if (servers.isEmpty) out.add(DiagItem(DiagLevel.warn, tr('Centralita'), tr('No hay ninguna línea configurada')));
    for (final a in servers.values) {
      final r = await _options(a.server, a.port);
      if (r == null) {
        out.add(DiagItem(DiagLevel.error, tr('Centralita {0}', [a.server]),
            tr('No responde a SIP en el puerto {0}. Revisa la red, la VPN o el cortafuegos.', [a.port])));
        continue;
      }
      out.add(DiagItem(DiagLevel.ok, tr('Centralita {0}', [a.server]),
          tr('Responde en {0} ms · {1}', [r.ms, r.server.isEmpty ? 'SIP' : r.server])));
      if (r.received.isNotEmpty && !localIps.contains(r.received)) {
        out.add(DiagItem(DiagLevel.warn, tr('NAT entre este equipo y la centralita'),
            tr('La centralita te ve como {0}. Si las llamadas conectan pero no se oye, añade la red de este equipo en «Local Networks» de FreePBX.', [r.received])));
      }
    }

    // 2) Registro de cada línea
    for (final l in app.lines.lines) {
      if (!l.account.enabled || !l.account.isComplete) continue;
      final ok = l.reg == RegState.registered;
      out.add(DiagItem(
          ok ? DiagLevel.ok : DiagLevel.error,
          tr('Línea {0} ({1})', [l.number, l.extension]),
          ok
              ? tr('Registrada')
              : '${l.reg.label}${l.regCode > 0 ? ' · ${l.regCode} ${l.regReason}' : ''}${l.reg == RegState.authError ? ' · ${tr('revisa la contraseña')}' : ''}'));
    }

    // 3) Audio
    final ins = app.audio.devices.where((d) => d.inputs > 0).length;
    final outs = app.audio.devices.where((d) => d.outputs > 0).length;
    out.add(DiagItem(
        ins > 0 && outs > 0 ? DiagLevel.ok : DiagLevel.error,
        tr('Audio'),
        tr('{0} micrófono(s) y {1} salida(s). Micrófono: {2} · Altavoz: {3}',
            [ins, outs, app.audio.captureName ?? tr('predeterminado'), app.audio.playbackName ?? tr('predeterminado')])));

    // 4) Panel de cola (AMI)
    final q = app.queue;
    if (q.config.enabled) {
      out.add(DiagItem(q.state == AmiState.connected ? DiagLevel.ok : DiagLevel.error, tr('Panel de cola (AMI)'),
          '${q.config.host}:${q.config.port} · ${q.state.name}'));
    }
    return out;
  }

  /// Texto para copiar y enviar a soporte.
  static String report(List<DiagItem> items) {
    final b = StringBuffer('NORYXS · ${tr('Diagnóstico')} · ${DateTime.now().toIso8601String().substring(0, 19)}\n');
    for (final i in items) {
      final mark = switch (i.level) { DiagLevel.ok => '✔', DiagLevel.warn => '⚠', DiagLevel.error => '✖', DiagLevel.info => '•' };
      b.writeln('$mark ${i.title}: ${i.detail}');
    }
    return b.toString();
  }

  static Future<List<String>> _localIps() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      return [for (final i in ifs) for (final a in i.addresses) a.address];
    } catch (_) {
      return [];
    }
  }

  /// Envía un SIP OPTIONS y devuelve tiempo de respuesta, cabecera Server e IP "received".
  static Future<({int ms, String server, String received})?> _options(String host, int port) async {
    RawDatagramSocket? sock;
    try {
      final addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
      final target = addrs.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addrs.first);
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final branch = 'z9hG4bK${Random().nextInt(1 << 30)}';
      final lp = sock.port;
      final req = 'OPTIONS sip:${target.address} SIP/2.0\r\n'
          'Via: SIP/2.0/UDP 0.0.0.0:$lp;branch=$branch;rport\r\n'
          'From: <sip:diag@noryxs>;tag=${Random().nextInt(1 << 30)}\r\n'
          'To: <sip:${target.address}>\r\n'
          'Call-ID: $branch\r\nCSeq: 1 OPTIONS\r\nMax-Forwards: 70\r\nContent-Length: 0\r\n\r\n';
      final sw = Stopwatch()..start();
      final done = Completer<({int ms, String server, String received})?>();
      sock.listen((ev) {
        if (ev != RawSocketEvent.read || done.isCompleted) return;
        final d = sock!.receive();
        if (d == null) return;
        final txt = utf8.decode(d.data, allowMalformed: true);
        if (!txt.startsWith('SIP/2.0')) return;
        final server = RegExp(r'^(Server|User-Agent):\s*(.+)$', multiLine: true, caseSensitive: false).firstMatch(txt)?.group(2)?.trim() ?? '';
        final received = RegExp(r'received=([0-9.]+)').firstMatch(txt)?.group(1) ?? '';
        done.complete((ms: sw.elapsedMilliseconds, server: server, received: received));
      });
      for (var i = 0; i < 3 && !done.isCompleted; i++) {
        sock.send(utf8.encode(req), target, port);
        await Future.any([done.future, Future.delayed(const Duration(milliseconds: 1000))]);
      }
      return done.isCompleted ? await done.future : null;
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }
}

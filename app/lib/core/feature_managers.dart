// Buzón de voz (MWI), teclas BLF / órbitas de aparcamiento, No molestar y desvíos.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';
import 'call_managers.dart';
import 'models.dart';
import 'sip_managers.dart';
import 'storage.dart';

// ---------------------------------------------------------------------------
// Buzón de voz (RFC 3842)
// ---------------------------------------------------------------------------

class VoicemailManager extends ChangeNotifier {
  /// accId → (nuevos, antiguos)
  final Map<int, ({int fresh, int old})> _byAcc = {};

  int newFor(SipLine l) => _byAcc[l.accId]?.fresh ?? 0;
  int oldFor(SipLine l) => _byAcc[l.accId]?.old ?? 0;
  int get totalNew => _byAcc.values.fold(0, (a, b) => a + b.fresh);

  void onEvent(EngineEvent e) {
    if (e.type != 'mwi') return;
    _byAcc[e.accId] = (fresh: e.intv('new'), old: e.intv('old'));
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Teclas BLF y órbitas de aparcamiento
// ---------------------------------------------------------------------------

enum BlfState { unknown, idle, ringing, busy, parked }

class BlfKey {
  BlfKey({required this.id, required this.ext, required this.label, this.park = false});
  final String id;
  String ext;
  String label;
  bool park; // órbita de aparcamiento (71–78)

  BlfState state = BlfState.unknown;
  String remote = '';
  int buddyId = -1;

  Map<String, dynamic> toJson() => {'id': id, 'ext': ext, 'label': label, 'park': park};
  factory BlfKey.fromJson(Map<String, dynamic> j) =>
      BlfKey(id: j['id'] as String, ext: j['ext'] as String? ?? '', label: j['label'] as String? ?? '', park: j['park'] as bool? ?? false);
}

class BlfManager extends ChangeNotifier {
  BlfManager(this._engine, this._storage, this._lines, this._calls);
  final SipEngine _engine;
  final AppStorage _storage;
  final MultiLineManager _lines;
  final CallSessionManager _calls;
  static const _file = 'blf.json';
  static const maxKeys = 6;

  final List<BlfKey> keys = [];
  int _subscribedAcc = -1;

  Future<void> load() async {
    final d = await _storage.read(_file);
    keys.clear();
    if (d is List) {
      keys.addAll(d.cast<Map<String, dynamic>>().map(BlfKey.fromJson));
    } else {
      keys.add(BlfKey(id: newId(), ext: '71', label: 'Órbita Park 71', park: true));
    }
    _lines.addListener(_syncSubscriptions);
    notifyListeners();
  }

  Future<void> save() async {
    await _storage.write(_file, keys.map((k) => k.toJson()).toList());
    _resubscribe();
    notifyListeners();
  }

  /// Las suscripciones salen por la primera línea registrada.
  SipLine? get _hostLine => _lines.lines.where((l) => l.reg == RegState.registered && l.accId >= 0).firstOrNull;

  void _syncSubscriptions() {
    final host = _hostLine;
    final acc = host?.accId ?? -1;
    if (acc != _subscribedAcc) _resubscribe();
  }

  void _resubscribe() {
    for (final k in keys) {
      if (k.buddyId >= 0) _engine.blfRemove(k.buddyId);
      k.buddyId = -1;
      k.state = BlfState.unknown;
    }
    final host = _hostLine;
    _subscribedAcc = host?.accId ?? -1;
    if (host == null) return;
    for (final k in keys) {
      // FreePBX publica el estado de cada órbita como *85<slot> (park-hints)
      if (k.ext.isNotEmpty) k.buddyId = _engine.blfAdd(host.accId, k.park ? '*85${k.ext}' : k.ext);
    }
  }

  void onEvent(EngineEvent e) {
    if (e.type != 'blf') return;
    final k = keys.where((x) => x.buddyId == e.intv('buddy_id')).firstOrNull;
    if (k == null) return;
    final ds = e.str('dialog_state');
    final recipient = e.str('direction') == 'recipient';
    k.remote = e.str('remote').isNotEmpty ? e.str('remote') : _userOf(e.str('remote_uri'));
    if (k.park) {
      k.state = (ds == 'confirmed' || ds == 'early') ? BlfState.parked : BlfState.idle;
    } else if (ds == 'early') {
      k.state = recipient ? BlfState.ringing : BlfState.busy;
    } else if (ds == 'confirmed') {
      k.state = BlfState.busy;
    } else if (ds == 'terminated' || ds.isEmpty) {
      // sub_state 5 = suscripción terminada (extensión sin hint / rechazada)
      k.state = e.intv('sub_state') == 5 && ds.isEmpty ? BlfState.unknown : BlfState.idle;
    }
    notifyListeners();
  }

  static String _userOf(String uri) {
    final m = RegExp(r'sips?:([^@;>]+)@').firstMatch(uri);
    return m?.group(1) ?? '';
  }

  /// Pulsación de tecla: llamar, capturar (**ext) o recuperar aparcada.
  String press(BlfKey k, SipLine line) {
    if (k.park) {
      if (k.state == BlfState.parked) {
        _calls.makeCall(line, k.ext);
        return 'Recuperando llamada aparcada en órbita ${k.ext}';
      }
      return 'Órbita ${k.ext} libre · pulsa «Aparcar» durante una llamada';
    }
    if (k.state == BlfState.ringing) {
      _calls.makeCall(line, '**${k.ext}');
      return 'Capturando la llamada de ${k.label} (**${k.ext})';
    }
    _calls.makeCall(line, k.ext);
    return 'Llamando a ${k.label} (${k.ext})';
  }
}

// ---------------------------------------------------------------------------
// No molestar y desvíos (códigos de servicio de FreePBX)
// ---------------------------------------------------------------------------

enum ForwardMode { off, always, busy, noAnswer }

extension ForwardModeText on ForwardMode {
  String get label => switch (this) {
        ForwardMode.off => 'Desactivado',
        ForwardMode.always => 'Siempre (incondicional *72)',
        ForwardMode.busy => 'Si está ocupado (*90)',
        ForwardMode.noAnswer => 'Si no contesta (*52)',
      };
  String get onCode => switch (this) { ForwardMode.always => '*72', ForwardMode.busy => '*90', ForwardMode.noAnswer => '*52', _ => '' };
  String get offCode => switch (this) { ForwardMode.always => '*73', ForwardMode.busy => '*91', ForwardMode.noAnswer => '*53', _ => '' };
}

class PbxFeatureManager extends ChangeNotifier {
  PbxFeatureManager(this._engine, this._storage, this._lines, this._calls);
  final SipEngine _engine;
  final AppStorage _storage;
  final MultiLineManager _lines;
  final CallSessionManager _calls;
  static const _file = 'features.json';

  bool dnd = false;
  ForwardMode forwardMode = ForwardMode.off;
  String forwardTarget = '';
  String forwardLineId = ''; // cuenta a la que se aplicó el desvío

  Future<void> load() async {
    final s = await _storage.read(_file);
    if (s is Map<String, dynamic>) {
      dnd = s['dnd'] as bool? ?? false;
      forwardMode = ForwardMode.values.firstWhere((m) => m.name == s['fwdMode'], orElse: () => ForwardMode.off);
      forwardTarget = s['fwdTarget'] as String? ?? '';
      forwardLineId = s['fwdLine'] as String? ?? '';
    }
    _engine.setDnd(dnd);
  }

  Future<void> _save() async {
    notifyListeners();
    await _storage.write(_file, {'dnd': dnd, 'fwdMode': forwardMode.name, 'fwdTarget': forwardTarget, 'fwdLine': forwardLineId});
  }

  List<SipLine> get _registered => _lines.lines.where((l) => l.reg == RegState.registered).toList();

  /// No molestar: local (486 inmediato) + FreePBX (*78 / *79) en todas las líneas.
  Future<String> setDnd(bool on) async {
    dnd = on;
    _engine.setDnd(on);
    var i = 0;
    for (final l in _registered) {
      Timer(Duration(milliseconds: 600 * i++), () => _calls.serviceCall(l, on ? '*78' : '*79'));
    }
    await _save();
    return on ? 'No molestar activado · las llamadas van al buzón' : 'No molestar desactivado';
  }

  /// Desvío en FreePBX para la línea indicada. Funciona aunque el ordenador esté apagado.
  Future<String?> setForward(ForwardMode mode, String target, SipLine line) async {
    final t = target.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (mode != ForwardMode.off && t.isEmpty) return 'Introduce el número de destino del desvío';
    if (line.reg != RegState.registered) return '${line.label} no está registrada';

    final prev = forwardMode;
    if (prev != ForwardMode.off) _calls.serviceCall(line, prev.offCode);
    if (mode != ForwardMode.off) {
      Timer(Duration(milliseconds: prev != ForwardMode.off ? 1500 : 0), () => _calls.serviceCall(line, '${mode.onCode}$t'));
    }
    forwardMode = mode;
    forwardTarget = mode == ForwardMode.off ? '' : t;
    forwardLineId = line.account.id;
    await _save();
    return null;
  }
}

/// Carpeta de grabaciones: Documentos/NORYXS Grabaciones
String recordingPathFor(CallSession c, SipLine? line) {
  final home = appHome();
  final dir = Directory('$home${Platform.pathSeparator}Documents${Platform.pathSeparator}NORYXS Grabaciones');
  dir.createSync(recursive: true);
  final t = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final who = (c.remoteNumber.isEmpty ? 'oculto' : c.remoteNumber).replaceAll(RegExp(r'[^0-9A-Za-z+]'), '');
  return '${dir.path}${Platform.pathSeparator}${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}_L${line?.number ?? 0}_$who.wav';
}

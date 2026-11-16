import 'dart:convert';
import 'dart:io';

import 'app_controller.dart';
import 'feature_managers.dart';
import 'i18n.dart';
import 'models.dart';

/// Configuración automática de puestos: un puesto ya configurado exporta un paquete
/// cifrado con PIN (líneas con contraseñas, teclas BLF, cola, etiquetas, plantillas de
/// WhatsApp y códecs) y los demás lo importan desde un fichero, un enlace o un QR.
/// No toca la centralita: solo copia la configuración de la app.
class Provisioning {
  static const scheme = 'noryxs:provision?d=';
  static const fileExt = 'noryxs';

  /// Paquete en claro (JSON). Incluye contraseñas: solo sale de aquí cifrado.
  static Map<String, dynamic> _build() {
    final app = AppController.I;
    return {
      'v': 1,
      'app': 'NORYXS',
      'created': DateTime.now().toIso8601String(),
      'accounts': [
        for (final a in app.accounts.accounts) {...a.toJson(), 'password': app.accounts.password(a) ?? ''},
      ],
      'blf': app.blf.keys.map((k) => k.toJson()).toList(),
      'queue': {...app.queue.config.toJson(), 'password': app.engine.secretGet('ami_password') ?? ''},
      'tags': {for (final t in app.history.tags) t.id: t.label},
      'whatsapp': app.whatsapp.templates,
      'codecs': [for (final c in app.audio.codecs) {'id': c.key, 'on': c.value}],
    };
  }

  /// Texto cifrado "SSP1:…" o null si no se pudo cifrar.
  /// El JSON se comprime (gzip) antes de cifrar para que quepa en un QR.
  static String? export(String pin) =>
      AppController.I.engine.pinSeal('Z:${base64.encode(gzip.encode(utf8.encode(jsonEncode(_build()))))}', pin);

  /// Enlace para el QR o para enviarlo por correo/mensaje.
  static String link(String sealed) => '$scheme${Uri.encodeComponent(sealed)}';

  /// Extrae el paquete cifrado de un enlace, de un texto pegado o del contenido de un fichero.
  static String? extract(String input) {
    var s = input.trim();
    if (s.startsWith('noryxs:')) {
      final i = s.indexOf('d=');
      if (i < 0) return null;
      s = Uri.decodeComponent(s.substring(i + 2));
    }
    final m = RegExp(r'SSP1:[A-Za-z0-9+/=]+').firstMatch(s);
    return m?.group(0);
  }

  /// Descarga un paquete desde una dirección http(s) (p. ej. el servidor interno).
  static Future<String?> download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      return extract(await res.transform(utf8.decoder).join());
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Descifra y aplica. Devuelve un mensaje de error o null si todo fue bien.
  static Future<String?> apply(String sealed, String pin) async {
    final app = AppController.I;
    var plain = app.engine.pinUnseal(sealed, pin);
    if (plain == null) return tr('PIN incorrecto o paquete dañado');
    if (plain.startsWith('Z:')) {
      try {
        plain = utf8.decode(gzip.decode(base64.decode(plain.substring(2))));
      } catch (_) {
        return tr('El paquete no es válido');
      }
    }
    final Map<String, dynamic> p;
    try {
      p = jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      return tr('El paquete no es válido');
    }

    // Líneas: sustituyen a las actuales (con sus contraseñas, al almacén seguro)
    final accs = (p['accounts'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    if (accs.isNotEmpty) {
      for (final l in app.lines.lines) {
        if (l.accId >= 0) app.engine.removeAccount(l.accId);
      }
      app.accounts.accounts
        ..clear()
        ..addAll(accs.map(SipAccountConfig.fromJson));
      for (final j in accs) {
        final pwd = j['password'] as String? ?? '';
        if (pwd.isNotEmpty) app.engine.secretSet('sip_password_${j['id']}', pwd);
      }
      await app.accounts.save();
      app.lines.sync(app.accounts.accounts);
      app.registration.applyAll();
    }

    final blf = p['blf'];
    if (blf is List) {
      app.blf.keys
        ..clear()
        ..addAll(blf.whereType<Map<String, dynamic>>().map(BlfKey.fromJson));
      await app.blf.save();
    }

    final q = p['queue'];
    if (q is Map<String, dynamic>) {
      app.queue.config.fromJson(q);
      await app.queue.save(password: q['password'] as String?);
    }

    final tags = p['tags'];
    if (tags is Map<String, dynamic>) await app.history.renameTags(tags.map((k, v) => MapEntry(k, '$v')));

    final wa = p['whatsapp'];
    if (wa is List && wa.isNotEmpty) await app.whatsapp.save(wa.whereType<String>().toList());

    final codecs = p['codecs'];
    if (codecs is List && codecs.isNotEmpty) {
      await app.audio.setCodecs([
        for (final c in codecs.whereType<Map<String, dynamic>>()) MapEntry(c['id'] as String, c['on'] as bool? ?? true),
      ]);
    }
    return null;
  }

  /// Guarda el paquete en un fichero .noryxs.
  static Future<bool> saveTo(String path, String sealed) async {
    try {
      await File(path).writeAsString('NORYXS · configuración de puesto (cifrada con PIN)\n$sealed\n');
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';
import 'phone_info.dart';
import 'storage.dart';

/// WhatsApp sin servidor: abre WhatsApp Desktop / Web con el chat del cliente y el mensaje
/// ya escrito (enlace oficial wa.me). El envío lo confirma la persona en WhatsApp.
class WhatsAppManager extends ChangeNotifier {
  WhatsAppManager(this._storage);
  final AppStorage _storage;
  static const _file = 'whatsapp.json';
  static const _channel = MethodChannel('noryxs/window');

  /// Plantillas (texto libre; {nombre} se sustituye por el nombre del cliente).
  List<String> templates = [];

  static List<String> get defaults => [
        tr('Hola {nombre}, le escribimos a raíz de nuestra llamada.'),
        tr('Le enviamos la ubicación del hotel: '),
        tr('Confirmamos su reserva. Cualquier duda, responda a este mensaje.'),
        tr('Gracias por su llamada. Quedamos a su disposición.'),
      ];

  Future<void> load() async {
    final j = await _storage.read(_file);
    templates = j is List ? j.whereType<String>().toList() : defaults;
    if (templates.isEmpty) templates = defaults;
  }

  Future<void> save(List<String> list) async {
    templates = list.where((t) => t.trim().isNotEmpty).toList();
    notifyListeners();
    await _storage.write(_file, templates);
  }

  /// Número en formato internacional sin '+' (wa.me), o null si no es un número externo.
  static String? waNumber(String raw) {
    final c = PhoneNumbers.canonical(raw);
    if (!c.startsWith('+')) return null;
    final d = c.substring(1);
    return d.length >= 8 ? d : null;
  }

  static String fill(String template, String name) => template.replaceAll('{nombre}', name).replaceAll('{name}', name);

  /// Abre el chat. Devuelve false si no se pudo abrir.
  static Future<bool> open(String number, String text) async {
    final n = waNumber(number);
    if (n == null) return false;
    final url = 'https://wa.me/$n?text=${Uri.encodeComponent(text)}';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else {
        await _channel.invokeMethod('openExternal', {'url': url});
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

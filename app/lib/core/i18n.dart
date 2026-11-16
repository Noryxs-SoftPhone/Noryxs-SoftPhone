import 'dart:ui' show PlatformDispatcher;

import 'i18n_ca.dart';
import 'i18n_en.dart';

/// Traducción de la interfaz sin paquetes externos: el texto en castellano es la clave.
/// `tr('Llamando a {0}', [numero])`. Si falta la traducción se muestra el castellano.
class I18n {
  /// 'es', 'ca' o 'en' (lo fija la app según la preferencia y el idioma del sistema).
  static String lang = 'es';

  static const supported = ['es', 'ca', 'en'];

  /// Preferencia del usuario → idioma efectivo. En automático manda el idioma del sistema:
  /// catalán → catalán, castellano → castellano, inglés → inglés; cualquier otro → inglés.
  static String resolve(String pref) {
    if (supported.contains(pref)) return pref;
    try {
      final locales = PlatformDispatcher.instance.locales;
      final code = (locales.isNotEmpty ? locales.first : PlatformDispatcher.instance.locale).languageCode.toLowerCase();
      return supported.contains(code) ? code : 'en';
    } catch (_) {
      return 'en';
    }
  }
}

String tr(String es, [List<Object?> args = const []]) {
  var s = switch (I18n.lang) {
    'en' => kEnglish[es] ?? es,
    'ca' => kCatalan[es] ?? es,
    _ => es,
  };
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'storage.dart';

/// Preferencias de interfaz: tema (claro / oscuro / automático) e idioma.
/// Se cargan antes de arrancar la app para pintar el splash y el resto con el tema correcto.
class UiPrefs extends ChangeNotifier {
  UiPrefs._();
  static final UiPrefs I = UiPrefs._();
  static const _file = 'ui.json';
  AppStorage? _storage;

  /// 'system' | 'light' | 'dark'
  String theme = 'system';

  /// 'system' | 'es' | 'en'
  String lang = 'system';

  Future<void> load() async {
    try {
      _storage = await AppStorage.open();
      final j = await _storage!.read(_file);
      if (j is Map<String, dynamic>) {
        theme = j['theme'] as String? ?? 'system';
        lang = j['lang'] as String? ?? 'system';
      }
    } catch (_) {}
  }

  bool isNight(Brightness platform) => theme == 'dark' || (theme == 'system' && platform == Brightness.dark);

  Future<void> set({String? theme, String? lang}) async {
    if (theme != null) this.theme = theme;
    if (lang != null) this.lang = lang;
    notifyListeners();
    await _storage?.write(_file, {'theme': this.theme, 'lang': this.lang});
  }
}

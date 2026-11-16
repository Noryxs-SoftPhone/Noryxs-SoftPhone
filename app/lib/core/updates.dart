import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'storage.dart';

/// Versión de esta compilación (CI: --dart-define=APP_VERSION=… desde pubspec.yaml).
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// Aviso de actualización sin servidor: la app mira un `latest.json` en una carpeta
/// compartida del hotel (NAS, recurso de red de Windows, carpeta montada en macOS/Linux).
///   {"version": "1.0.1", "notes": "…", "macos": "NORYXS-Terminal-macOS.zip",
///    "windows": "NORYXS-Terminal-Windows.zip", "linux": "NORYXS-Terminal_1.0.1-1_amd64.deb"}
/// Lo genera `packaging/publicar_en_carpeta.sh`.
class UpdateManager extends ChangeNotifier {
  UpdateManager(this._storage);
  final AppStorage _storage;
  static const _file = 'updates.json';

  String folder = '';
  String? availableVersion;
  String notes = '';
  String? installerPath;
  DateTime? lastCheck;
  String lastResult = '';
  Timer? _timer;

  Future<void> load() async {
    final j = await _storage.read(_file);
    if (j is Map<String, dynamic>) folder = j['folder'] as String? ?? '';
    // Primera comprobación al poco de arrancar y después cada 6 horas
    Timer(const Duration(seconds: 20), check);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  Future<void> setFolder(String path) async {
    folder = path.trim();
    notifyListeners();
    await _storage.write(_file, {'folder': folder});
    await check();
  }

  /// Comprueba la carpeta. Devuelve el texto del resultado.
  Future<String> check() async {
    lastCheck = DateTime.now();
    if (folder.isEmpty) return lastResult = 'sin carpeta';
    try {
      final f = File('$folder${Platform.pathSeparator}latest.json');
      if (!await f.exists()) {
        lastResult = 'no hay latest.json';
      } else {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final v = j['version'] as String? ?? '';
        final key = Platform.isMacOS ? 'macos' : (Platform.isWindows ? 'windows' : (Platform.isLinux ? 'linux' : ''));
        final file = j[key] as String? ?? '';
        if (v.isNotEmpty && isNewer(v, kAppVersion) && file.isNotEmpty) {
          availableVersion = v;
          notes = j['notes'] as String? ?? '';
          installerPath = '$folder${Platform.pathSeparator}$file';
          lastResult = 'nueva';
        } else {
          availableVersion = null;
          lastResult = 'al día';
        }
      }
    } catch (_) {
      lastResult = 'carpeta no accesible';
    }
    notifyListeners();
    return lastResult;
  }

  /// Abre el instalador (zip / .deb) con la aplicación del sistema.
  Future<void> install() async {
    final p = installerPath;
    if (p == null) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', p]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', p]);
      } else {
        await Process.run('xdg-open', [p]);
      }
    } catch (_) {}
  }

  void dismiss() {
    availableVersion = null;
    notifyListeners();
  }

  /// "1.2.10" > "1.2.9"
  static bool isNewer(String a, String b) {
    List<int> parts(String v) => v.split(RegExp(r'[.+-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < 4; i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

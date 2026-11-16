// Persistencia local en JSON (sin servicios externos).
// Las contraseñas NO se guardan aquí: van al almacén seguro del sistema.
import 'dart:convert';
import 'dart:io';

/// Carpeta personal de la app. En iOS no existe HOME: el contenedor de la app
/// es el padre de la carpeta temporal (`…/Application/<uuid>/tmp`).
String appHome() {
  final env = Platform.environment;
  final h = env['HOME'] ?? env['USERPROFILE'];
  if (h != null && h.isNotEmpty) return h;
  return Directory.systemTemp.parent.path;
}

class AppStorage {
  AppStorage._(this.dir);
  final Directory dir;

  static Future<AppStorage> open() async {
    final env = Platform.environment;
    String base;
    if (Platform.isMacOS || Platform.isIOS) {
      base = '${appHome()}/Library/Application Support/NORYXS';
    } else if (Platform.isWindows) {
      base = '${env['APPDATA']}\\NORYXS';
    } else {
      base = '${env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config'}/noryxs';
    }
    final d = Directory(base);
    await d.create(recursive: true);
    if (Platform.isMacOS) await _migrateFromSandbox(d, env['HOME']!);
    return AppStorage._(d);
  }

  /// Las primeras versiones iban en el sandbox de macOS: traer sus datos una vez.
  static Future<void> _migrateFromSandbox(Directory dest, String home) async {
    final old = Directory('$home/Library/Containers/com.noryxs.noryxsTerminal/Data/Library/Application Support/NORYXS');
    if (!await old.exists()) return;
    for (final name in ['accounts.json', 'settings.json', 'contacts.json', 'history.json']) {
      final src = File('${old.path}/$name');
      final dst = File('${dest.path}/$name');
      if (await src.exists() && !await dst.exists()) await src.copy(dst.path);
    }
  }

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  Future<dynamic> read(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Escritura atómica: fichero temporal + rename.
  Future<void> write(String name, Object data) async {
    final f = _file(name);
    final tmp = _file('$name.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
    await tmp.rename(f.path);
  }
}

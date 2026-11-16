import 'dart:io';

import 'package:flutter/services.dart';

/// Abre un enlace en el navegador del sistema (macOS, Windows, Linux; iPhone por el canal nativo).
Future<bool> openLink(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    } else {
      await const MethodChannel('noryxs/window').invokeMethod('openExternal', {'url': url});
    }
    return true;
  } catch (_) {
    return false;
  }
}

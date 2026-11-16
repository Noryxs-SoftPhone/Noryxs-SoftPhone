import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';

/// Reproductor de grabaciones y mensajes de voz (WAV) por el altavoz, con el motor PJSIP.
class PlaybackManager extends ChangeNotifier {
  PlaybackManager(this._engine);
  final SipEngine _engine;

  String? path; // fichero en reproducción
  int durationMs = 0;
  int positionMs = 0;
  Timer? _tick;

  bool isPlaying(String p) => path == p;

  /// Devuelve un mensaje de error o null.
  String? play(String p) {
    if (!File(p).existsSync()) return 'No se encuentra el archivo de la grabación';
    stop();
    final d = _engine.playStart(p);
    if (d < 0) return 'No se pudo reproducir la grabación';
    path = p;
    durationMs = d;
    positionMs = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final pos = _engine.playPos();
      if (pos < 0) return stop();
      positionMs = pos;
      notifyListeners();
    });
    notifyListeners();
    return null;
  }

  void seek(int ms) {
    if (path == null) return;
    _engine.playSeek(ms.clamp(0, durationMs));
    positionMs = ms;
    notifyListeners();
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
    if (path != null) _engine.playStop();
    path = null;
    positionMs = 0;
    notifyListeners();
  }

  /// Evento del motor: fin del fichero.
  void onEnded() => stop();

  /// Muestra el fichero en el explorador de archivos del sistema.
  static Future<void> reveal(String p) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', p]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', p]);
      } else {
        await Process.run('xdg-open', [File(p).parent.path]);
      }
    } catch (_) {}
  }
}

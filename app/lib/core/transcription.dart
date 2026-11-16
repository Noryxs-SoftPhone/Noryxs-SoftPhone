import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/native_bindings.dart';
import '../engine/sip_engine.dart';
import 'models.dart';
import 'storage.dart';

/// Transcripción local de las grabaciones (whisper.cpp, modelo Base incluido en la app).
///
/// - Todo ocurre en el propio ordenador: el audio no sale nunca del equipo.
/// - Se lanza sola al colgar una llamada grabada, en segundo plano y de una en una.
///   Si hay una llamada en curso, espera a que termine para no robar CPU al audio.
/// - El texto se guarda **cifrado** (misma clave del Llavero que las notas) en
///   transcripts.json, indexado por la ruta del WAV.
class TranscriptionManager extends ChangeNotifier {
  TranscriptionManager(this._storage, this._engine);
  final AppStorage _storage;
  final SipEngine _engine;
  static const _file = 'transcripts.json';
  static const modelFile = 'ggml-base-q5_1.bin';

  /// Texto en claro (en memoria) por ruta de grabación.
  final Map<String, String> _text = {};

  /// Cifrado tal cual está en disco (para no recifrar lo que no cambia).
  final Map<String, String> _sealed = {};

  /// Grabaciones que no se pudieron transcribir (sin voz, fichero dañado…).
  final Set<String> _failed = {};

  final List<String> _queue = [];
  String? working;
  bool Function() hasActiveCall = () => false;

  /// false en iOS o si falta el modelo: la interfaz no muestra nada.
  bool get available => NativeEngine.open().canTranscribe && modelPath != null;

  String? text(String wav) => _text[wav];
  bool isPending(String wav) => working == wav || _queue.contains(wav);
  bool failed(String wav) => _failed.contains(wav);

  /// Texto de todas las grabaciones de una llamada (para buscar en el historial).
  String textFor(HistoryEntry e) => [for (final r in e.recordings) _text[r] ?? ''].join('\n');

  /// Ruta del modelo dentro de la app (asset de Flutter).
  static String? get modelPath {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final rel = 'flutter_assets${sep}assets${sep}models$sep$modelFile';
    final candidates = <String>[
      if (Platform.isMacOS) '${File(Platform.resolvedExecutable).parent.parent.path}${sep}Frameworks${sep}App.framework${sep}Resources$sep$rel',
      '$exeDir${sep}data$sep$rel', // Windows y Linux
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> load(List<HistoryEntry> entries) async {
    final d = await _storage.read(_file);
    if (d is Map<String, dynamic>) {
      for (final kv in d.entries) {
        if (kv.value is! String) continue;
        final plain = _engine.unseal(kv.value as String);
        if (plain == null) continue;
        _sealed[kv.key] = kv.value as String;
        if (plain.isEmpty) {
          _failed.add(kv.key);
        } else {
          _text[kv.key] = plain;
        }
      }
    }
    await prune(entries); // llamadas que ya salieron del historial
    notifyListeners();
    // Grabaciones de los últimos 7 días que quedaron sin transcribir (app cerrada a mitad, etc.)
    final since = DateTime.now().subtract(const Duration(days: 7));
    for (final e in entries.where((e) => e.start.isAfter(since))) {
      enqueue(e.recordings);
    }
  }

  /// Pone en cola las grabaciones que aún no tienen texto.
  void enqueue(Iterable<String> wavs) {
    if (!available) return;
    var added = false;
    for (final w in wavs) {
      if (_text.containsKey(w) || _failed.contains(w) || isPending(w)) continue;
      _queue.add(w);
      added = true;
    }
    if (added) {
      notifyListeners();
      _pump();
    }
  }

  /// Vuelve a intentarlo (botón "Transcribir" de una grabación fallida).
  void retry(String wav) {
    _failed.remove(wav);
    _sealed.remove(wav);
    enqueue([wav]);
  }

  bool _running = false;

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      final model = modelPath;
      while (_queue.isNotEmpty && model != null) {
        // El grabador cierra el WAV al colgar; y nunca en mitad de una llamada.
        await Future.delayed(const Duration(seconds: 2));
        while (hasActiveCall()) {
          await Future.delayed(const Duration(seconds: 3));
        }
        final wav = _queue.removeAt(0);
        if (!File(wav).existsSync()) continue;
        working = wav;
        notifyListeners();
        final threads = math.max(2, math.min(6, Platform.numberOfProcessors ~/ 2));
        String? out;
        try {
          out = await Isolate.run(() => NativeEngine.open().transcribe(wav, model, threads: threads));
        } catch (_) {
          out = null;
        }
        working = null;
        final clean = (out ?? '').trim();
        if (clean.isEmpty) {
          _failed.add(wav);
        } else {
          _text[wav] = clean;
        }
        final sealed = _engine.seal(clean);
        if (sealed != null) _sealed[wav] = sealed;
        notifyListeners();
        await _save();
      }
    } finally {
      _running = false;
    }
  }

  /// Borra la transcripción de las grabaciones que ya no existen en el historial.
  Future<void> prune(Iterable<HistoryEntry> entries) async {
    final keep = {for (final e in entries) ...e.recordings};
    final before = _sealed.length;
    _sealed.removeWhere((k, _) => !keep.contains(k));
    _text.removeWhere((k, _) => !keep.contains(k));
    if (_sealed.length != before) await _save();
  }

  Future<void> _save() => _storage.write(_file, Map<String, String>.of(_sealed));

  /// Texto listo para copiar (sin las marcas de tiempo si se pide).
  static String plain(String t, {bool stamps = true}) =>
      stamps ? t : LineSplitter.split(t).map((l) => l.replaceFirst(RegExp(r'^\[\d+:\d+\]\s*'), '')).join(' ');
}

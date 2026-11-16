// Genera el icono de la app (macOS) a partir del emblema NORYXS.
// Ejecutar: flutter test test/gen_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/ui/logo.dart';

Future<void> _render(int px, String path) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = px.toDouble();
  // Rejilla de iconos de macOS: contenido 824/1024 centrado, con sombra.
  final inner = s * 824 / 1024;
  final off = (s - inner) / 2;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(off, off + s * 0.012, inner, inner), Radius.circular(inner * 0.27)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
  );
  canvas.translate(off, off);
  NoryxsLogoPainter().paint(canvas, Size(inner, inner));
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// iOS: icono cuadrado a sangre, sin transparencia (el sistema redondea las esquinas).
Future<void> _renderIos(int px, String path) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = px.toDouble();
  canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = const Color(0xFF16171B));
  // El emblema ocupa todo; se recorta el filo redondeado propio para que iOS aplique el suyo
  canvas.save();
  canvas.scale(1.0);
  NoryxsLogoPainter().paint(canvas, Size(s, s));
  canvas.restore();
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('generar AppIcon iOS', () async {
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final re = RegExp(r'Icon-App-([0-9.]+)x[0-9.]+@([0-9])x\.png');
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final m = re.firstMatch(f.path.split('/').last);
      if (m == null) continue;
      final px = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
      await _renderIos(px, f.path);
    }
  });

  test('generar AppIcon', () async {
    const dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final px in [16, 32, 64, 128, 256, 512, 1024]) {
      await _render(px, '$dir/app_icon_$px.png');
    }
  });
}

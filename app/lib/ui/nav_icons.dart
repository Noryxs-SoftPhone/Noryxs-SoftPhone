import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Iconos propios de la barra inferior: trazo fino homogéneo (estilo línea premium),
/// con relleno suave de acento cuando la pestaña está activa.
enum NavGlyph { terminal, voicemail, contacts, history, settings, moon, forward, headset, queue }

class NavIcon extends StatelessWidget {
  const NavIcon(this.glyph, {super.key, required this.color, this.fill, this.size = 22});
  final NavGlyph glyph;
  final Color color;

  /// Relleno tenue (pestaña activa) o null.
  final Color? fill;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _NavPainter(glyph, color, fill)));
}

class _NavPainter extends CustomPainter {
  _NavPainter(this.glyph, this.color, this.fill);
  final NavGlyph glyph;
  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // diseño en rejilla de 24
    canvas.scale(s);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final soft = fill == null ? null : (Paint()..color = fill!);
    final dot = Paint()..color = color;

    switch (glyph) {
      case NavGlyph.terminal:
        // Terminal de sobremesa: cuerpo redondeado, pantalla y teclado de 3×2
        final body = RRect.fromLTRBR(5, 2.5, 19, 21.5, const Radius.circular(3.6));
        if (soft != null) canvas.drawRRect(body, soft);
        canvas.drawRRect(body, line);
        canvas.drawRRect(RRect.fromLTRBR(8, 5.5, 16, 9.5, const Radius.circular(1.4)), line);
        for (var r = 0; r < 2; r++) {
          for (var c = 0; c < 3; c++) {
            canvas.drawCircle(Offset(8.6 + c * 3.4, 13.2 + r * 3.4), 0.95, dot);
          }
        }
      case NavGlyph.voicemail:
        // Cinta de buzón: dos bobinas unidas
        if (soft != null) {
          canvas.drawCircle(const Offset(6.5, 12), 4, soft);
          canvas.drawCircle(const Offset(17.5, 12), 4, soft);
        }
        canvas.drawCircle(const Offset(6.5, 12), 4, line);
        canvas.drawCircle(const Offset(17.5, 12), 4, line);
        canvas.drawLine(const Offset(6.5, 16), const Offset(17.5, 16), line);
        canvas.drawCircle(const Offset(6.5, 12), 1.1, dot);
        canvas.drawCircle(const Offset(17.5, 12), 1.1, dot);
      case NavGlyph.contacts:
        // Tarjeta de contacto con busto
        final card = RRect.fromLTRBR(3, 4, 21, 20, const Radius.circular(3.2));
        if (soft != null) canvas.drawRRect(card, soft);
        canvas.drawRRect(card, line);
        canvas.drawCircle(const Offset(9.5, 10.5), 2.4, line);
        final bust = Path()
          ..moveTo(5.6, 16.8)
          ..cubicTo(6.2, 14.6, 7.8, 13.6, 9.5, 13.6)
          ..cubicTo(11.2, 13.6, 12.8, 14.6, 13.4, 16.8);
        canvas.drawPath(bust, line);
        canvas.drawLine(const Offset(15.5, 9.5), const Offset(18.2, 9.5), line);
        canvas.drawLine(const Offset(15.5, 12.8), const Offset(18.2, 12.8), line);
      case NavGlyph.history:
        // Reloj con flecha de "volver atrás"
        final arc = Rect.fromCircle(center: const Offset(12.5, 12), radius: 8.3);
        if (soft != null) canvas.drawCircle(const Offset(12.5, 12), 8.3, soft);
        canvas.drawArc(arc, math.pi * 0.95, math.pi * 1.75, false, line);
        final head = Path()
          ..moveTo(2.6, 8.4)
          ..lineTo(4.4, 11.6)
          ..lineTo(7.4, 9.6);
        canvas.drawPath(head, line);
        canvas.drawLine(const Offset(12.5, 7.6), const Offset(12.5, 12.2), line);
        canvas.drawLine(const Offset(12.5, 12.2), const Offset(15.4, 14.1), line);
      case NavGlyph.moon:
        // No molestar: luna creciente
        final moon = Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8))
          ..fillType = PathFillType.evenOdd;
        final bite = Path()..addOval(Rect.fromCircle(center: const Offset(16.2, 8.6), radius: 6.6));
        final shape = Path.combine(PathOperation.difference, moon, bite);
        if (soft != null) canvas.drawPath(shape, soft);
        canvas.drawPath(shape, line);
      case NavGlyph.forward:
        // Desvío: flecha que gira
        final p = Path()
          ..moveTo(5, 19)
          ..lineTo(5, 13)
          ..cubicTo(5, 10.2, 7.2, 8, 10, 8)
          ..lineTo(19, 8);
        canvas.drawPath(p, line);
        final h = Path()
          ..moveTo(15.2, 4.2)
          ..lineTo(19, 8)
          ..lineTo(15.2, 11.8);
        canvas.drawPath(h, line);
      case NavGlyph.headset:
        // Cascos con micrófono
        final arc = Path()..addArc(Rect.fromCircle(center: const Offset(12, 13), radius: 7.5), math.pi, math.pi);
        canvas.drawPath(arc, line);
        final l = RRect.fromLTRBR(3.6, 12.5, 7.4, 19, const Radius.circular(1.8));
        final r = RRect.fromLTRBR(16.6, 12.5, 20.4, 19, const Radius.circular(1.8));
        if (soft != null) {
          canvas.drawRRect(l, soft);
          canvas.drawRRect(r, soft);
        }
        canvas.drawRRect(l, line);
        canvas.drawRRect(r, line);
        final mic = Path()
          ..moveTo(18.5, 19)
          ..cubicTo(18.5, 21, 16.5, 21.5, 13.5, 21.5);
        canvas.drawPath(mic, line);
      case NavGlyph.queue:
        // Cola: dos personas
        canvas.drawCircle(const Offset(9, 8.5), 3, line);
        final b1 = Path()
          ..moveTo(3.5, 19)
          ..cubicTo(4, 15.4, 6.2, 13.6, 9, 13.6)
          ..cubicTo(11.8, 13.6, 14, 15.4, 14.5, 19);
        canvas.drawPath(b1, line);
        canvas.drawCircle(const Offset(16.5, 9.2), 2.4, line);
        final b2 = Path()
          ..moveTo(16.2, 13.8)
          ..cubicTo(18.6, 13.9, 20.2, 15.6, 20.6, 18.6);
        canvas.drawPath(b2, line);
      case NavGlyph.settings:
        // Ajustes como deslizadores: tres pistas con mando
        if (soft != null) canvas.drawRRect(RRect.fromLTRBR(3, 3.5, 21, 20.5, const Radius.circular(4)), soft);
        const ys = [7.0, 12.0, 17.0];
        const xs = [15.0, 8.5, 13.0];
        for (var i = 0; i < 3; i++) {
          // la pista se corta alrededor del mando
          canvas.drawLine(Offset(4.5, ys[i]), Offset(xs[i] - 2.2, ys[i]), line);
          canvas.drawLine(Offset(xs[i] + 2.2, ys[i]), Offset(19.5, ys[i]), line);
          canvas.drawCircle(Offset(xs[i], ys[i]), 2.2, line);
        }
    }
  }

  @override
  bool shouldRepaint(_NavPainter old) => old.glyph != glyph || old.color != color || old.fill != fill;
}

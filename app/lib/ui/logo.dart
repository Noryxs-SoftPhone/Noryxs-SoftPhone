import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Emblema NORYXS: monograma "N" en oro cepillado sobre grafito,
/// con ondas de señal (voz IP) en la esquina superior derecha.
class NoryxsLogo extends StatelessWidget {
  const NoryxsLogo({super.key, this.size = 40, this.glow = 0});
  final double size;

  /// 0..1 — halo dorado (para el splash).
  final double glow;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: NoryxsLogoPainter(glow: glow)),
      );
}

class NoryxsLogoPainter extends CustomPainter {
  NoryxsLogoPainter({this.glow = 0});
  final double glow;

  static const goldLight = Color(0xFFF3E2B3);
  static const goldMid = Color(0xFFCBA765);
  static const goldDeep = Color(0xFF8C6D33);

  static Shader goldShader(Rect r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [goldLight, goldMid, goldDeep, goldMid],
        stops: [0.0, 0.38, 0.72, 1.0],
      ).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final radius = Radius.circular(s * 0.27);
    final rr = RRect.fromRectAndRadius(rect, radius);

    if (glow > 0) {
      canvas.drawRRect(
        rr.inflate(s * 0.06),
        Paint()
          ..color = goldMid.withValues(alpha: 0.28 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.18),
      );
    }

    // Cuerpo grafito con luz superior
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2D33), Color(0xFF16171B), Color(0xFF0E0F12)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    // Brillo sutil
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawCircle(
      Offset(s * 0.25, -s * 0.15),
      s * 0.7,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(s * 0.25, -s * 0.15), radius: s * 0.7)),
    );
    canvas.restore();

    // Filo dorado
    canvas.drawRRect(
      rr.deflate(s * 0.022),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, s * 0.026)
        ..shader = goldShader(rect),
    );

    // Monograma N
    final gold = Paint()
      ..shader = goldShader(rect)
      ..style = PaintingStyle.fill;
    final l = s * 0.27, r = s * 0.66, t = s * 0.30, b = s * 0.73;
    final w = s * 0.085;
    final n = Path()
      ..moveTo(l, b)
      ..lineTo(l, t)
      ..lineTo(l + w, t)
      ..lineTo(r - w, b - s * 0.13)
      ..lineTo(r - w, t + s * 0.10)
      ..lineTo(r, t + s * 0.10)
      ..lineTo(r, b)
      ..lineTo(r - w, b)
      ..lineTo(l + w, t + s * 0.13)
      ..lineTo(l + w, b)
      ..close();
    canvas.drawPath(n, gold);

    // Ondas de señal
    final c = Offset(r - w / 2, t + s * 0.03);
    for (var i = 0; i < 2; i++) {
      final rad = s * (0.075 + i * 0.07);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: rad),
        -math.pi * 0.47,
        math.pi * 0.47,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.9, s * 0.032)
          ..shader = goldShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(NoryxsLogoPainter old) => old.glow != glow;
}

/// Texto "NORYXS" en oro.
class GoldText extends StatelessWidget {
  const GoldText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: NoryxsLogoPainter.goldShader,
        child: Text(text, style: style),
      );
}

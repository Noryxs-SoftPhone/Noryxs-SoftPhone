import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// Efecto táctil de tecla física (como `.tactile-btn:active` del diseño).
class Tactile extends StatefulWidget {
  const Tactile({super.key, required this.child, this.onTap, this.onLongPress, this.tooltip});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  @override
  State<Tactile> createState() => _TactileState();
}

class _TactileState extends State<Tactile> {
  bool _down = false;
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget w = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? 0.985 : 1,
          duration: const Duration(milliseconds: 70),
          child: AnimatedSlide(
            offset: _down ? const Offset(0, 0.012) : Offset.zero,
            duration: const Duration(milliseconds: 70),
            child: _HoverScope(hover: _hover && enabled, child: widget.child),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 500), child: w);
    return w;
  }
}

/// Permite a los hijos saber si el ratón está encima.
class _HoverScope extends InheritedWidget {
  const _HoverScope({required this.hover, required super.child});
  final bool hover;
  static bool of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_HoverScope>()?.hover ?? false;
  @override
  bool updateShouldNotify(_HoverScope old) => old.hover != hover;
}

enum NxTone { dark, surface, white, gold, emerald, red, redSoft, amber }

/// Botón del diseño (rounded-2xl / rounded-xl) con variantes de color.
class NxButton extends StatelessWidget {
  const NxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = NxTone.surface,
    this.icon,
    this.height = 40,
    this.radius = 16,
    this.fontSize = 12,
    this.iconColor,
    this.tooltip,
    this.bold = false,
  });
  final String label;
  final VoidCallback? onTap;
  final NxTone tone;
  final IconData? icon;
  final double height, radius, fontSize;
  final Color? iconColor;
  final String? tooltip;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      tooltip: tooltip,
      child: Builder(builder: (context) {
        final hover = _HoverScope.of(context);
        final (bg, bgHover, fg, border) = switch (tone) {
          NxTone.dark => (NxColors.dark, Colors.black, Colors.white, NxColors.dark),
          NxTone.surface => (NxColors.surface, NxColors.surfaceHover, NxColors.text, NxColors.border),
          NxTone.white => (Colors.white, NxColors.surfaceHover, NxColors.text, NxColors.border),
          NxTone.gold => (NxColors.goldSoft, const Color(0xFFF4EAD6), NxColors.goldDark, NxColors.gold),
          NxTone.emerald => (NxColors.green600, NxColors.greenText, Colors.white, NxColors.green600),
          NxTone.red => (NxColors.red, NxColors.redText, Colors.white, NxColors.red),
          NxTone.redSoft => (NxColors.redSoft, const Color(0xFFFEE2E2), NxColors.redText, NxColors.redBorder),
          NxTone.amber => (NxColors.amber, const Color(0xFFD97706), Colors.white, NxColors.amber),
        };
        final enabled = onTap != null;
        return Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hover ? bgHover : bg,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
              boxShadow: tone == NxTone.dark || tone == NxTone.emerald || tone == NxTone.red
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 4, offset: const Offset(0, 2))]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 3, color: iconColor ?? (tone == NxTone.dark ? NxColors.gold : fg)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: fontSize, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text,
      {super.key, this.fg = NxColors.gray700, this.bg = NxColors.surfaceHover, this.border, this.mono = false, this.size = 10, this.compact = false, this.round = false});
  final String text;
  final Color fg, bg;
  final Color? border;
  final bool mono, compact, round;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: compact ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1) : const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(round ? 99 : 5),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Text(text,
            style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w600, fontFamily: mono ? kMono : kSans, height: 1.3)),
      );
}

/// LED de estado; con [pulse] emite un anillo dorado (led-pulse del diseño).
class Led extends StatefulWidget {
  const Led(this.color, {super.key, this.size = 8, this.pulse = false});
  final Color color;
  final double size;
  final bool pulse;
  @override
  State<Led> createState() => _LedState();
}

class _LedState extends State<Led> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(Led old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (widget.pulse)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = Curves.easeOut.transform((_c.value / 0.7).clamp(0, 1));
                return Transform.scale(
                  scale: 0.92 + 0.9 * t,
                  child: Container(
                    width: widget.size + 6,
                    height: widget.size + 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.9 * (1 - t))),
                  ),
                );
              },
            ),
          Container(decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        ]),
      );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Led(color, size: size);
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.size = 11});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(color: NxColors.gray400, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: 0.9));
}

/// Caja gris del diseño (rounded-2xl, borde).
class NxPanel extends StatelessWidget {
  const NxPanel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor, this.radius = 16});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? NxColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? NxColors.border),
        ),
        child: child,
      );
}

// Compatibilidad con pantallas existentes
class DarkButton extends StatelessWidget {
  const DarkButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 40, this.fontSize = 12.5});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height, fontSize;
  @override
  Widget build(BuildContext context) =>
      NxButton(label: label, onTap: onPressed, icon: icon, tone: NxTone.dark, height: height, fontSize: fontSize, radius: 12);
}

class LightButton extends StatelessWidget {
  const LightButton({super.key, required this.label, required this.onPressed, this.height = 40, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final double height;
  final IconData? icon;
  @override
  Widget build(BuildContext context) =>
      NxButton(label: label, onTap: onPressed, icon: icon, tone: NxTone.white, height: height, radius: 12);
}

/// Botón "Llamar" de las listas (agenda, historial, buzón).
class SquareCallButton extends StatelessWidget {
  const SquareCallButton({super.key, required this.onTap, this.label = 'Llamar', this.light = false});
  final VoidCallback? onTap;
  final String label;
  final bool light;
  @override
  Widget build(BuildContext context) => NxButton(
        label: label,
        onTap: onTap,
        tone: light ? NxTone.white : NxTone.dark,
        height: 30,
        radius: 12,
        fontSize: 11.5,
      );
}

// ---- Colores por estado ----

({Color fg, Color bg, Color dot}) lineStatusColors(LineStatus s) => switch (s) {
      LineStatus.free => (fg: NxColors.gray400, bg: NxColors.surface, dot: NxColors.green),
      LineStatus.ringing => (fg: NxColors.goldDark, bg: NxColors.goldSoft, dot: NxColors.gold),
      LineStatus.busy => (fg: NxColors.greenText, bg: NxColors.greenSoft, dot: NxColors.green),
      LineStatus.held => (fg: NxColors.amberText, bg: NxColors.amberSoft, dot: NxColors.amber),
      LineStatus.disconnected => (fg: NxColors.red, bg: NxColors.redSoft, dot: NxColors.red500),
    };

Color regColor(RegState r) => switch (r) {
      RegState.registered => NxColors.green,
      RegState.registering => NxColors.amber,
      RegState.unregistered => NxColors.gray400,
      _ => NxColors.red500,
    };

String fmtDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

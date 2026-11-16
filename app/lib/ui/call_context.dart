import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/phone_info.dart';
import '../core/support_managers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Colores de las 4 etiquetas (fijos; el nombre se configura).
({Color fg, Color bg, Color border, Color dot}) tagColors(String color) => switch (color) {
      'gold' => (fg: NxColors.goldDark, bg: NxColors.goldSoft, border: NxColors.gold, dot: NxColors.gold),
      'red' => (fg: NxColors.redText, bg: NxColors.redSoft, border: NxColors.redBorder, dot: NxColors.red500),
      'sky' => (fg: NxColors.skyText, bg: NxColors.skySoft, border: const Color(0xFF7DD3FC), dot: NxColors.sky),
      _ => (fg: NxColors.greenText, bg: NxColors.greenSoft, border: NxColors.greenBorder, dot: NxColors.green),
    };

class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.tag, required this.selected, this.onTap, this.small = false});
  final CallTag tag;
  final bool selected;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = tagColors(tag.color);
    return Tactile(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 1.5 : 3.5),
        decoration: BoxDecoration(
          color: selected ? c.bg : NxColors.card,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? c.border : NxColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: small ? 5 : 6, height: small ? 5 : 6, decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? c.dot : NxColors.gray400)),
          SizedBox(width: small ? 4 : 5),
          Text(tag.label,
              style: TextStyle(
                  fontSize: small ? 9.5 : 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c.fg : NxColors.gray500)),
        ]),
      ),
    );
  }
}

/// Fila de las 4 etiquetas.
class TagRow extends StatelessWidget {
  const TagRow({super.key, required this.selected, required this.onToggle, this.small = false});
  final List<String> selected;
  final ValueChanged<String>? onToggle;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final h = AppController.I.history;
    return Wrap(spacing: 5, runSpacing: 5, children: [
      for (final t in h.tags)
        TagPill(tag: t, selected: selected.contains(t.id), small: small, onTap: onToggle == null ? null : () => onToggle!(t.id)),
    ]);
  }
}

/// Editor de nota rápida (2 líneas). Se guarda solo al escribir.
class QuickNoteField extends StatefulWidget {
  const QuickNoteField({super.key, required this.initial, required this.onChanged, this.autofocus = false});
  final String initial;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  @override
  State<QuickNoteField> createState() => _QuickNoteFieldState();
}

class _QuickNoteFieldState extends State<QuickNoteField> {
  late final _ctl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctl,
        autofocus: widget.autofocus,
        minLines: 2,
        maxLines: 2,
        maxLength: CallHistoryManager.maxNote,
        onChanged: widget.onChanged,
        inputFormatters: [LengthLimitingTextInputFormatter(CallHistoryManager.maxNote)],
        style: const TextStyle(fontSize: 12, height: 1.35),
        decoration: InputDecoration(
          hintText: tr('Ej. Llamar mañana a las 10:00 — Ref. 402'),
          counterText: '',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );
}

/// Bloque "Nota rápida + etiquetas" plegable (tarjeta de llamada e historial).
class CallContextBlock extends StatefulWidget {
  const CallContextBlock({
    super.key,
    required this.note,
    required this.tags,
    required this.onNote,
    required this.onToggleTag,
    this.initiallyOpen = false,
    this.trailing,
  });
  final String note;
  final List<String> tags;
  final ValueChanged<String> onNote;
  final ValueChanged<String> onToggleTag;
  final bool initiallyOpen;
  final Widget? trailing;
  @override
  State<CallContextBlock> createState() => _CallContextBlockState();
}

class _CallContextBlockState extends State<CallContextBlock> {
  late bool _open = widget.initiallyOpen || widget.note.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final has = widget.note.trim().isNotEmpty || widget.tags.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Tactile(
          onTap: () => setState(() => _open = !_open),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit_note_rounded, size: 16, color: has ? NxColors.goldDark : NxColors.gray500),
            const SizedBox(width: 4),
            Text(has ? tr('Nota y etiquetas') : tr('Añadir nota'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: has ? NxColors.goldDark : NxColors.gray500)),
            Icon(_open ? Icons.expand_less : Icons.expand_more, size: 15, color: NxColors.gray400),
          ]),
        ),
        const Spacer(),
        if (!_open && widget.tags.isNotEmpty) TagRow(selected: widget.tags, onToggle: null, small: true),
        if (widget.trailing != null) ...[const SizedBox(width: 6), widget.trailing!],
      ]),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.topCenter,
        child: !_open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  QuickNoteField(initial: widget.note, onChanged: widget.onNote),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: TagRow(selected: widget.tags, onToggle: widget.onToggleTag)),
                    Icon(Icons.lock_outline, size: 11, color: NxColors.gray400),
                    const SizedBox(width: 3),
                    Text(tr('Cifrado local'), style: TextStyle(fontSize: 9.5, color: NxColors.gray400)),
                  ]),
                ]),
              ),
      ),
    ]);
  }
}

/// Origen del número + última nota (antes de descolgar). [dark] para fondos oscuros.
class CallerContext extends StatelessWidget {
  const CallerContext({super.key, required this.number, this.dark = false, this.showLastNote = true});
  final String number;
  final bool dark;
  final bool showLastNote;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final info = PhoneNumbers.lookup(number);
    final last = showLastNote ? app.history.lastContextFor(number) : null;
    if (info == null && last == null) return const SizedBox.shrink();
    String two(int v) => v.toString().padLeft(2, '0');
    final muted = dark ? const Color(0xFF9CA3AF) : NxColors.gray500;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (info != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(info.display, style: TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w500)),
        ),
      if (last != null) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.08) : NxColors.goldSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dark ? NxColors.gold.withValues(alpha: 0.35) : NxColors.goldBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              last.note.trim().isNotEmpty
                  ? tr('Última nota ({0}/{1}): {2}', [two(last.start.day), two(last.start.month), last.note.trim().replaceAll('\n', ' ')])
                  : tr('Última llamada ({0}/{1})', [two(last.start.day), two(last.start.month)]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: dark ? const Color(0xFFE6D3A3) : NxColors.goldDark),
            ),
            if (last.tags.isNotEmpty) ...[const SizedBox(height: 4), TagRow(selected: last.tags, onToggle: null, small: true)],
          ]),
        ),
      ],
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/phone_info.dart';
import 'agenda_tab.dart';
import 'call_context.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.onCall});
  final void Function(String number, {SipLine? line}) onCall;
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  HistoryType? _filter;
  String? _tagFilter;
  final Set<String> _open = {};
  final app = AppController.I;

  String _date(DateTime d) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(d.hour)}:${two(d.minute)}';
    if (now.difference(d).inMinutes < 1) return 'Ahora mismo';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Hoy, $time';
    final y = now.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Ayer, $time';
    return '${two(d.day)}/${two(d.month)} $time';
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar historial'),
        content: const Text('Se eliminarán todas las llamadas del historial y sus notas y etiquetas. No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(style: TextButton.styleFrom(foregroundColor: NxColors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) app.history.clear();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? dot}) => Tactile(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? NxColors.goldSoft : NxColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? NxColors.gold : NxColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)), const SizedBox(width: 5)],
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? NxColors.goldDark : NxColors.gray500)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final h = app.history;
    final list = h.entries.where((e) => (_filter == null || e.type == _filter) && (_tagFilter == null || e.tags.contains(_tagFilter))).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Row(children: [
          const Expanded(child: Text('Historial de Llamadas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (h.entries.isNotEmpty) Tactile(onTap: _confirmClear, child: const Text('Borrar', style: TextStyle(fontSize: 11, color: NxColors.gray400))),
          const SizedBox(width: 10),
          const Text('Registro Local SIP', style: TextStyle(fontSize: 11, color: NxColors.gray400)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in <(HistoryType?, String)>[(null, 'Todas'), (HistoryType.incoming, 'Entrantes'), (HistoryType.outgoing, 'Salientes'), (HistoryType.missed, 'Perdidas')])
            _chip(f.$2, _filter == f.$1, () => setState(() => _filter = f.$1)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in h.tags)
            _chip(t.label, _tagFilter == t.id, () => setState(() => _tagFilter = _tagFilter == t.id ? null : t.id), dot: tagColors(t.color).dot),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Column(children: [
              Icon(Icons.schedule, size: 32, color: NxColors.gray400),
              SizedBox(height: 8),
              Text('No hay llamadas', style: TextStyle(color: NxColors.gray500, fontSize: 12)),
            ]),
          ),
        for (final e in list) ...[_row(e), const SizedBox(height: 8)],
      ],
    );
  }

  Widget _row(HistoryEntry e) {
    final (badge, color) = switch (e.type) {
      HistoryType.incoming => ('↙ Entrante', NxColors.green600),
      HistoryType.outgoing => ('↗ Saliente', const Color(0xFF0284C7)),
      HistoryType.missed => ('✕ Perdida', NxColors.red),
    };
    final known = app.contacts.lookup(e.number);
    final name = known.isNotEmpty ? known : (e.name.isNotEmpty ? e.name : e.number);
    final line = e.lineNumber >= 1 && e.lineNumber <= app.lines.lines.length ? app.lines.lines[e.lineNumber - 1] : null;
    final open = _open.contains(e.id);
    final info = PhoneNumbers.lookup(e.number);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: open ? Colors.white : NxColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? NxColors.goldBorder : NxColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Tactile(
          onTap: () => setState(() => open ? _open.remove(e.id) : _open.add(e.id)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                  Flexible(
                    child: Text('  • Línea ${e.lineNumber}  • ${_date(e.start)}',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: NxColors.gray400)),
                  ),
                  if (e.note.trim().isNotEmpty) ...[const SizedBox(width: 6), const Icon(Icons.sticky_note_2_outlined, size: 12, color: NxColors.goldDark)],
                  for (final id in e.tags)
                    if (app.history.tagById(id) != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: tagColors(app.history.tagById(id)!.color).dot)),
                      ),
                ]),
                const SizedBox(height: 2),
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: e.number),
                    TextSpan(text: '  (${fmtDuration(Duration(seconds: e.durationSec))})', style: const TextStyle(color: NxColors.gray400)),
                  ]),
                  style: const TextStyle(fontFamily: kMono, fontSize: 11, color: NxColors.gray600),
                ),
                if (info != null && !info.internal) Text(info.display, style: const TextStyle(fontSize: 10, color: NxColors.gray400)),
                if (!open && e.note.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(e.note.trim().replaceAll('\n', ' '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: NxColors.goldDark)),
                  ),
              ]),
            ),
            if (known.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tactile(
                  tooltip: 'Guardar en agenda',
                  onTap: () => showDialog(context: context, builder: (_) => ContactDialog(initialNumber: e.number)),
                  child: const Icon(Icons.person_add_alt, size: 16, color: NxColors.gray400),
                ),
              ),
            NxButton(label: 'Devolver', tone: NxTone.white, height: 30, radius: 12, onTap: () => widget.onCall(e.number, line: line)),
          ]),
        ),
        if (open) ...[
          const Divider(height: 18, color: NxColors.border),
          CallContextBlock(
            key: ValueKey('hctx-${e.id}'),
            note: e.note,
            tags: e.tags,
            initiallyOpen: true,
            onNote: (v) => app.history.setNote(e, v),
            onToggleTag: (id) => app.history.toggleTag(e, id),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: NxButton(
              label: 'Copiar resumen',
              icon: Icons.copy_rounded,
              iconColor: NxColors.goldDark,
              tone: NxTone.white,
              height: 30,
              radius: 10,
              fontSize: 11,
              tooltip: 'Copia un comprobante de la llamada para pegarlo en un correo o expediente',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: app.history.summary(e, contactName: known)));
                app.showToast('Resumen de la llamada copiado al portapapeles');
              },
            ),
          ),
        ],
      ]),
    );
  }
}

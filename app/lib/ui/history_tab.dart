import 'dart:io';
import '../core/i18n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/phone_info.dart';
import '../core/playback.dart';
import '../core/search.dart';
import 'agenda_tab.dart';
import 'call_context.dart';
import 'theme.dart';
import 'whatsapp_ui.dart';
import 'transcript_view.dart';
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
  bool _pendingOnly = false;
  final Set<String> _open = {};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(HistoryEntry e) {
    final known = app.nameFor(e.number);
    return matchesQuery(_search.text, texts: [
      known,
      e.name,
      e.number,
      e.note,
      PhoneNumbers.lookup(e.number)?.display ?? '',
      for (final id in e.tags) app.history.tagById(id)?.label ?? '',
      app.transcripts.textFor(e),
    ], numbers: [e.number]);
  }
  final app = AppController.I;

  String _date(DateTime d) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(d.hour)}:${two(d.minute)}';
    if (now.difference(d).inMinutes < 1) return tr('Ahora mismo');
    if (d.year == now.year && d.month == now.month && d.day == now.day) return tr('Hoy, {0}', [time]);
    final y = now.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return tr('Ayer, {0}', [time]);
    return '${two(d.day)}/${two(d.month)} $time';
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Borrar historial')),
        content: Text(tr('Se eliminarán todas las llamadas del historial y sus notas, etiquetas y transcripciones. No se puede deshacer.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar'))),
          TextButton(style: TextButton.styleFrom(foregroundColor: NxColors.red), onPressed: () => Navigator.pop(context, true), child: Text(tr('Borrar'))),
        ],
      ),
    );
    if (ok == true) {
      await app.history.clear();
      await app.transcripts.prune(const []);
    }
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
    final pending = h.pendingMissed;
    final list = (_pendingOnly ? pending : h.entries).where((e) => (_filter == null || e.type == _filter) && (_tagFilter == null || e.tags.contains(_tagFilter)) && _matches(e)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Row(children: [
          Expanded(child: Text(tr('Historial de Llamadas'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (h.entries.isNotEmpty) Tactile(onTap: _confirmClear, child: Text(tr('Borrar'), style: TextStyle(fontSize: 11, color: NxColors.gray400))),
          const SizedBox(width: 10),
          Text(tr('Registro Local SIP'), style: TextStyle(fontSize: 11, color: NxColors.gray400)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: tr('Buscar por nombre, número, nota o etiqueta…'),
            fillColor: NxColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(_search.clear)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in <(HistoryType?, String)>[(null, tr('Todas')), (HistoryType.incoming, tr('Entrantes')), (HistoryType.outgoing, tr('Salientes')), (HistoryType.missed, tr('Perdidas'))])
            _chip(f.$2, _filter == f.$1, () => setState(() => _filter = f.$1)),
          if (pending.isNotEmpty || _pendingOnly)
            _chip(tr('Pendientes de devolver ({0})', [pending.length]), _pendingOnly, () => setState(() => _pendingOnly = !_pendingOnly), dot: NxColors.red),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in h.tags)
            _chip(t.label, _tagFilter == t.id, () => setState(() => _tagFilter = _tagFilter == t.id ? null : t.id), dot: tagColors(t.color).dot),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Column(children: [
              Icon(Icons.schedule, size: 32, color: NxColors.gray400),
              SizedBox(height: 8),
              Text(tr('No hay llamadas'), style: TextStyle(color: NxColors.gray500, fontSize: 12)),
            ]),
          ),
        for (final e in list) ...[_row(e), const SizedBox(height: 8)],
      ],
    );
  }

  Widget _row(HistoryEntry e) {
    final (badge, color) = switch (e.type) {
      HistoryType.incoming => (tr('↙ Entrante'), NxColors.green600),
      HistoryType.outgoing => (tr('↗ Saliente'), NxColors.skyText),
      HistoryType.missed => (tr('✕ Perdida'), NxColors.red),
    };
    final known = app.nameFor(e.number);
    final name = known.isNotEmpty ? known : (e.name.isNotEmpty ? e.name : e.number);
    final line = e.lineNumber >= 1 && e.lineNumber <= app.lines.lines.length ? app.lines.lines[e.lineNumber - 1] : null;
    final open = _open.contains(e.id);
    final info = PhoneNumbers.lookup(e.number);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: open ? NxColors.card : NxColors.surface,
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
                  if (app.history.isPending(e)) ...[const SizedBox(width: 5), Pill(tr('Pendiente'), size: 8.5, compact: true, fg: NxColors.redText, bg: NxColors.redSoft)],
                  Flexible(
                    child: Text(tr('  • Línea {0}  • {1}', [e.lineNumber, _date(e.start)]),
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: NxColors.gray400)),
                  ),
                  if (e.note.trim().isNotEmpty) ...[const SizedBox(width: 6), Icon(Icons.sticky_note_2_outlined, size: 12, color: NxColors.goldDark)],
                  if (e.recordings.isNotEmpty) ...[const SizedBox(width: 5), Icon(Icons.graphic_eq_rounded, size: 13, color: NxColors.red)],
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
                    TextSpan(text: '  (${fmtDuration(Duration(seconds: e.durationSec))})', style: TextStyle(color: NxColors.gray400)),
                  ]),
                  style: TextStyle(fontFamily: kMono, fontSize: 11, color: NxColors.gray600),
                ),
                if (info != null && !info.internal) Text(info.display, style: TextStyle(fontSize: 10, color: NxColors.gray400)),
                if (!open && e.note.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(e.note.trim().replaceAll('\n', ' '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: NxColors.goldDark)),
                  ),
              ]),
            ),
            if (known.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tactile(
                  tooltip: tr('Guardar en agenda'),
                  onTap: () => showDialog(context: context, builder: (_) => ContactDialog(initialNumber: e.number)),
                  child: Icon(Icons.person_add_alt, size: 16, color: NxColors.gray400),
                ),
              ),
            NxButton(label: tr('Devolver'), tone: NxTone.white, height: 30, radius: 12, onTap: () => widget.onCall(e.number, line: line)),
          ]),
        ),
        if (open) ...[
          Divider(height: 18, color: NxColors.border),
          for (final r in e.recordings) ...[_RecordingPlayer(path: r), TranscriptView(path: r, query: _search.text), const SizedBox(height: 8)],
          CallContextBlock(
            key: ValueKey('hctx-${e.id}'),
            note: e.note,
            tags: e.tags,
            initiallyOpen: true,
            onNote: (v) => app.history.setNote(e, v),
            onToggleTag: (id) => app.history.toggleTag(e, id),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (app.history.isPending(e)) ...[
              NxButton(
                label: tr('Marcar atendida'),
                icon: Icons.check_rounded,
                tone: NxTone.white,
                height: 30,
                radius: 10,
                fontSize: 11,
                tooltip: tr('Quitar de pendientes (por ejemplo, si se atendió desde otro teléfono)'),
                onTap: () => app.history.markHandled(e),
              ),
              const SizedBox(width: 6),
            ],
            WhatsAppButton(number: e.number, name: known.isNotEmpty ? known : e.name),
            const SizedBox(width: 6),
            NxButton(
              label: tr('Copiar resumen'),
              icon: Icons.copy_rounded,
              iconColor: NxColors.goldDark,
              tone: NxTone.white,
              height: 30,
              radius: 10,
              fontSize: 11,
              tooltip: tr('Copia un comprobante de la llamada para pegarlo en un correo o expediente'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: app.history.summary(e, contactName: known)));
                app.showToast(tr('Resumen de la llamada copiado al portapapeles'));
              },
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Reproductor de una grabación de la llamada (WAV en Documentos/NORYXS Grabaciones).
class _RecordingPlayer extends StatelessWidget {
  const _RecordingPlayer({required this.path});
  final String path;

  String _t(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final pb = app.playback;
    return ListenableBuilder(
      listenable: pb,
      builder: (context, _) {
        final playing = pb.isPlaying(path);
        final exists = File(path).existsSync();
        final dur = playing ? pb.durationMs : 0;
        final pos = playing ? pb.positionMs : 0;
        return Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: NxColors.border)),
          child: Row(children: [
            Tactile(
              tooltip: playing ? tr('Detener') : tr('Escuchar la grabación'),
              onTap: !exists
                  ? null
                  : () {
                      if (playing) {
                        pb.stop();
                      } else {
                        final err = pb.play(path);
                        if (err != null) app.showToast(err);
                      }
                    },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: exists ? NxColors.dark : NxColors.gray400, shape: BoxShape.circle),
                child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: !exists
                  ? Text(tr('Grabación no encontrada (se movió o se borró)'), style: TextStyle(fontSize: 10.5, color: NxColors.gray500))
                  : SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: NxColors.gold,
                        inactiveTrackColor: NxColors.border,
                        thumbColor: NxColors.goldDark,
                      ),
                      child: Slider(
                        value: dur == 0 ? 0 : pos.clamp(0, dur).toDouble(),
                        max: dur == 0 ? 1 : dur.toDouble(),
                        onChanged: playing ? (v) => pb.seek(v.round()) : null,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            if (exists) Text(playing ? '${_t(pos)} / ${_t(dur)}' : tr('Grabación'), style: TextStyle(fontFamily: kMono, fontSize: 10, color: NxColors.gray500)),
            const SizedBox(width: 6),
            if (exists)
              Tactile(
                tooltip: tr('Mostrar en la carpeta'),
                onTap: () => PlaybackManager.reveal(path),
                child: Icon(Icons.folder_open_outlined, size: 16, color: NxColors.gray500),
              ),
          ]),
        );
      },
    );
  }
}

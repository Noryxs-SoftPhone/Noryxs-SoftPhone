import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/i18n.dart';
import '../core/search.dart';
import '../core/transcription.dart';
import 'theme.dart';
import 'widgets.dart';

/// Transcripción de una grabación, bajo su reproductor en el historial.
/// Plegada muestra dos líneas; al desplegar, el texto completo con sus marcas de tiempo.
/// Resalta lo que se haya escrito en el buscador del historial.
class TranscriptView extends StatefulWidget {
  const TranscriptView({super.key, required this.path, this.query = ''});
  final String path;
  final String query;
  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tm = AppController.I.transcripts;
    return ListenableBuilder(
      listenable: tm,
      builder: (context, _) {
        if (!tm.available) return const SizedBox.shrink();
        final text = tm.text(widget.path);
        final Widget body;
        if (text != null) {
          body = _text(text);
        } else if (tm.isPending(widget.path)) {
          body = Row(children: [
            SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: NxColors.gold)),
            const SizedBox(width: 8),
            Text(tm.working == widget.path ? tr('Transcribiendo en este ordenador…') : tr('En cola para transcribir…'),
                style: TextStyle(fontSize: 10.5, color: NxColors.gray500)),
          ]);
        } else if (tm.failed(widget.path)) {
          body = Row(children: [
            Expanded(child: Text(tr('No se reconoció voz en la grabación'), style: TextStyle(fontSize: 10.5, color: NxColors.gray500))),
            _link(tr('Reintentar'), () => tm.retry(widget.path)),
          ]);
        } else {
          body = Row(children: [
            Expanded(child: Text(tr('Sin transcribir'), style: TextStyle(fontSize: 10.5, color: NxColors.gray500))),
            _link(tr('Transcribir'), () => tm.retry(widget.path)),
          ]);
        }
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: NxColors.goldSoft.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: NxColors.gold, width: 2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.notes_rounded, size: 13, color: NxColors.goldDark),
              const SizedBox(width: 5),
              Text(tr('Transcripción'), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: NxColors.goldDark)),
              const SizedBox(width: 6),
              Tooltip(
                message: tr('Generada en este ordenador: el audio no sale del equipo. Puede contener errores.'),
                child: Icon(Icons.lock_outline_rounded, size: 11, color: NxColors.gray400),
              ),
              const Spacer(),
              if (text != null) ...[
                Tactile(
                  tooltip: tr('Copiar transcripción'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    AppController.I.showToast(tr('Transcripción copiada'));
                  },
                  child: Icon(Icons.copy_rounded, size: 13, color: NxColors.gray500),
                ),
                const SizedBox(width: 8),
                Tactile(
                  tooltip: _open ? tr('Plegar') : tr('Ver completa'),
                  onTap: () => setState(() => _open = !_open),
                  child: AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more_rounded, size: 16, color: NxColors.gray500),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 5),
            AnimatedSize(duration: const Duration(milliseconds: 180), curve: Curves.easeOut, alignment: Alignment.topCenter, child: body),
          ]),
        );
      },
    );
  }

  Widget _link(String label, VoidCallback onTap) => Tactile(
        onTap: onTap,
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: NxColors.gold)),
      );

  Widget _text(String text) {
    final base = TextStyle(fontSize: 11.5, height: 1.45, color: NxColors.text);
    final stamp = TextStyle(fontFamily: kMono, fontSize: 9.5, color: NxColors.gray400);
    if (!_open) {
      return GestureDetector(
        onTap: () => setState(() => _open = true),
        child: Text.rich(
          TextSpan(children: _highlight(TranscriptionManager.plain(text, stamps: false), base)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final spans = <InlineSpan>[];
    for (final line in text.split('\n')) {
      final m = RegExp(r'^\[(\d+:\d+)\]\s*').firstMatch(line);
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
      if (m != null) {
        spans.add(TextSpan(text: '${m[1]}  ', style: stamp));
        spans.addAll(_highlight(line.substring(m.end), base));
      } else {
        spans.addAll(_highlight(line, base));
      }
    }
    return SelectableText.rich(TextSpan(children: spans));
  }

  /// Resalta la búsqueda (sin acentos ni mayúsculas, como el buscador).
  List<TextSpan> _highlight(String s, TextStyle style) {
    final q = foldText(widget.query.trim());
    if (q.length < 2) return [TextSpan(text: s, style: style)];
    final f = foldText(s);
    if (f.length != s.length) return [TextSpan(text: s, style: style)];
    final out = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = f.indexOf(q, i);
      if (j < 0) break;
      if (j > i) out.add(TextSpan(text: s.substring(i, j), style: style));
      out.add(TextSpan(
        text: s.substring(j, j + q.length),
        style: style.copyWith(fontWeight: FontWeight.w700, backgroundColor: NxColors.amberSoft, color: NxColors.amberText),
      ));
      i = j + q.length;
    }
    if (i < s.length) out.add(TextSpan(text: s.substring(i), style: style));
    return out;
  }
}

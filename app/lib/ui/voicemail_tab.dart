import 'package:flutter/material.dart';
import '../core/i18n.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Buzón de voz por línea (MWI, RFC 3842).
class VoicemailTab extends StatelessWidget {
  const VoicemailTab({super.key, required this.onCall});
  final void Function(String number, {SipLine? line}) onCall;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final vm = app.voicemail;
    final lines = app.lines.lines.where((l) => l.account.isComplete).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Buzón de Voz (MWI)'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(tr('Suscripción SIP RFC 3842 • FreePBX Voicemail'), style: TextStyle(fontSize: 11, color: NxColors.gray500)),
            ]),
          ),
          Tactile(
            onTap: () => app.dialVoicemail(app.lines.selectedLine),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: NxColors.dark, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Led(NxColors.gold, size: 7),
                SizedBox(width: 6),
                Text(tr('Llamar al Buzón (*97)'), style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(tr('Configura una cuenta SIP para recibir avisos de buzón'), textAlign: TextAlign.center, style: TextStyle(color: NxColors.gray500, fontSize: 12)),
          ),
        for (final l in lines) ...[
          _LineVoicemail(
            line: l,
            fresh: vm.newFor(l),
            old: vm.oldFor(l),
            onListen: () => onCall('*97', line: l),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: NxColors.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: NxColors.goldDark),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('FreePBX avisa por SIP de cuántos mensajes hay en cada línea. Para ver cada recado con remitente, hora y audio dentro del terminal, activa en FreePBX el envío del buzón por email: la lectura por IMAP es el siguiente paso.'),
                style: TextStyle(fontSize: 10.5, color: NxColors.gray600, height: 1.35),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _LineVoicemail extends StatelessWidget {
  const _LineVoicemail({required this.line, required this.fresh, required this.old, required this.onListen});
  final SipLine line;
  final int fresh, old;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final unread = fresh > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unread ? NxColors.goldSoft.withValues(alpha: 0.5) : NxColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: unread ? NxColors.gold.withValues(alpha: 0.6) : NxColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (unread) ...[Led(NxColors.gold, size: 8, pulse: true), const SizedBox(width: 6)],
              Text(line.account.name.isEmpty ? line.label : line.account.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Pill(tr('Línea {0} • Ext. {1}', [line.number, line.extension]), mono: true, size: 9, bg: NxColors.card, border: NxColors.border),
            ]),
            const SizedBox(height: 3),
            Text(
              unread ? tr('{0} mensaje{1} nuevo{2} • {3} escuchado{4}', [fresh, fresh == 1 ? '' : 's', fresh == 1 ? '' : 's', old, old == 1 ? '' : 's']) : tr('Sin mensajes nuevos • {0} guardado{1}', [old, old == 1 ? '' : 's']),
              style: TextStyle(fontFamily: kMono, fontSize: 11, color: unread ? NxColors.goldDark : NxColors.gray600),
            ),
            Text(line.reg == RegState.registered ? tr('Suscripción MWI activa') : tr('Línea sin registrar'),
                style: TextStyle(fontSize: 10, color: NxColors.gray400)),
          ]),
        ),
        NxButton(label: tr('Escuchar'), tone: NxTone.dark, height: 30, radius: 12, fontSize: 11, onTap: line.reg == RegState.registered ? onListen : null),
      ]),
    );
  }
}

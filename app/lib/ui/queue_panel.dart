import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/queue_manager.dart';
import 'theme.dart';
import 'widgets.dart';

/// Panel lateral "En espera": llamadas aguardando en la cola de FreePBX.
class QueuePanel extends StatefulWidget {
  const QueuePanel({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  Timer? _tick;
  final app = AppController.I;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && app.queue.callers.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = app.queue;
    final callers = q.callers;
    final myExt = app.lines.selectedLine.extension;
    final connected = q.state == AmiState.connected;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: NxColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Cabecera del panel
        Container(
          padding: const EdgeInsets.fromLTRB(16, 34, 14, 11),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NxColors.border))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (callers.isNotEmpty) ...[const Led(NxColors.gold, size: 7, pulse: true), const SizedBox(width: 6)],
                  Text('EN ESPERA • ${callers.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NxColors.text, letterSpacing: 0.9)),
                ]),
                const SizedBox(height: 2),
                Text(
                  connected ? 'Cola ${q.config.queues.join(', ')} • FreePBX' : q.stateText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: connected ? NxColors.gray500 : NxColors.red),
                ),
              ]),
            ),
            Tactile(
              onTap: widget.onClose,
              tooltip: 'Ocultar panel',
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: NxColors.border)),
                child: const Icon(Icons.chevron_right_rounded, size: 18, color: NxColors.gray500),
              ),
            ),
          ]),
        ),
        Expanded(
          child: callers.isEmpty
              ? _empty(connected)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  itemCount: callers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CallerCard(caller: callers[i], first: i == 0, myExt: myExt),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
          decoration: const BoxDecoration(color: NxColors.surface, border: Border(top: BorderSide(color: NxColors.border))),
          child: Text(
            'Atender pasa la llamada a tu ${app.lines.selectedLine.label.replaceFirst('LÍNEA', 'Línea')} (ext. $myExt); la conversación actual queda retenida.',
            style: const TextStyle(fontSize: 9.5, color: NxColors.gray400, height: 1.35),
          ),
        ),
      ]),
    );
  }

  Widget _empty(bool connected) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: NxColors.border)),
              child: Icon(connected ? Icons.hourglass_empty_rounded : Icons.link_off_rounded, size: 20, color: NxColors.gray400),
            ),
            const SizedBox(height: 10),
            Text(connected ? 'No hay llamadas en espera' : 'Panel de cola sin conexión',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NxColors.gray600)),
            const SizedBox(height: 4),
            Text(connected ? 'Las llamadas que entren mientras hablas aparecerán aquí.' : 'Revisa la configuración AMI en la pestaña SIP.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: NxColors.gray400)),
          ]),
        ),
      );
}

class _CallerCard extends StatelessWidget {
  const _CallerCard({required this.caller, required this.first, required this.myExt});
  final QueueCaller caller;
  final bool first;
  final String myExt;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final q = app.queue;
    final w = caller.waiting;
    final long = w.inSeconds >= 120;
    final contact = app.contacts.lookup(caller.number);
    final name = contact.isNotEmpty ? contact : caller.display;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: first ? NxColors.goldSoft.withValues(alpha: 0.6) : NxColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: first ? NxColors.gold : NxColors.border),
        boxShadow: first ? [BoxShadow(color: NxColors.gold.withValues(alpha: 0.16), spreadRadius: 3)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: first ? NxColors.dark : Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: first ? NxColors.dark : NxColors.border),
            ),
            child: Text('${caller.position == 0 ? 1 : caller.position}',
                style: TextStyle(fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w700, color: first ? NxColors.gold : NxColors.gray600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (name != caller.number && caller.number.isNotEmpty)
                Text(caller.number, style: const TextStyle(fontFamily: kMono, fontSize: 10.5, color: NxColors.gray500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Led(long ? NxColors.red500 : NxColors.gold, size: 6, pulse: true),
              const SizedBox(width: 4),
              Text(fmtDuration(w),
                  style: TextStyle(fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w700, color: long ? NxColors.red : NxColors.text)),
            ]),
            Text('Cola ${caller.queue}', style: const TextStyle(fontSize: 9.5, color: NxColors.gray400)),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 5,
            child: NxButton(
              label: caller.pickupRequested ? 'Pasando…' : 'Atender',
              icon: Icons.call,
              tone: NxTone.dark,
              height: 30,
              radius: 10,
              fontSize: 11,
              onTap: caller.pickupRequested
                  ? null
                  : () {
                      q.pickup(caller, myExt);
                      app.showToast('Atendiendo a $name · la llamada actual queda retenida');
                    },
            ),
          ),
          const SizedBox(width: 5),
          _IconBtn(icon: Icons.phone_forwarded_outlined, tooltip: 'Transferir a otra extensión', onTap: () => _transfer(context, caller)),
          const SizedBox(width: 5),
          _IconBtn(
            icon: Icons.voicemail_rounded,
            tooltip: 'Enviar al buzón de la ext. $myExt',
            onTap: () {
              q.toVoicemail(caller, myExt);
              app.showToast('$name enviado al buzón de la ext. $myExt');
            },
          ),
          const SizedBox(width: 5),
          _IconBtn(
            icon: Icons.call_end_rounded,
            tooltip: 'Colgar',
            danger: true,
            onTap: () {
              q.hangup(caller);
              app.showToast('Llamada de $name finalizada');
            },
          ),
        ]),
      ]),
    );
  }

  Future<void> _transfer(BuildContext context, QueueCaller c) async {
    final ctl = TextEditingController();
    final app = AppController.I;
    final dest = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transferir llamada en espera'),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: ctl,
            autofocus: true,
            style: const TextStyle(fontFamily: kMono),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'Extensión destino (ej. 201)'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Transferir')),
        ],
      ),
    );
    if (dest != null && dest.trim().isNotEmpty) {
      app.queue.transfer(c, dest.trim());
      app.showToast('Transferida a la extensión ${dest.trim()}');
    }
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap, this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Tactile(
        onTap: onTap,
        tooltip: tooltip,
        child: Container(
          width: 32,
          height: 30,
          decoration: BoxDecoration(
            color: danger ? NxColors.redSoft : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: danger ? NxColors.redBorder : NxColors.border),
          ),
          child: Icon(icon, size: 15, color: danger ? NxColors.redText : NxColors.gray600),
        ),
      );
}

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/i18n.dart';
import '../core/whatsapp.dart';
import 'theme.dart';
import 'widgets.dart';

/// Botón WhatsApp (solo para números externos): elige plantilla, edita y abre WhatsApp.
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({super.key, required this.number, this.name = ''});
  final String number;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (WhatsAppManager.waNumber(number) == null) return const SizedBox.shrink();
    return NxButton(
      label: 'WhatsApp',
      icon: Icons.chat_rounded,
      iconColor: const Color(0xFF25D366),
      tone: NxTone.white,
      height: 30,
      radius: 10,
      fontSize: 11,
      tooltip: tr('Enviar un WhatsApp a este número'),
      onTap: () => showDialog(context: context, builder: (_) => _WhatsAppDialog(number: number, name: name)),
    );
  }
}

class _WhatsAppDialog extends StatefulWidget {
  const _WhatsAppDialog({required this.number, required this.name});
  final String number, name;
  @override
  State<_WhatsAppDialog> createState() => _WhatsAppDialogState();
}

class _WhatsAppDialogState extends State<_WhatsAppDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    return AlertDialog(
      title: Text(tr('WhatsApp a {0}', [widget.name.isNotEmpty ? widget.name : widget.number])),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Plantillas'), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: NxColors.gray500)),
          const SizedBox(height: 6),
          for (final t in app.whatsapp.templates)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Tactile(
                onTap: () => setState(() => _text.text = WhatsAppManager.fill(t, widget.name)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: NxColors.border)),
                  child: Text(WhatsAppManager.fill(t, widget.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NxColors.text)),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(hintText: tr('Escribe o elige una plantilla…')),
          ),
          const SizedBox(height: 6),
          Text(tr('Se abre WhatsApp con el mensaje escrito; pulsa Enviar allí.'), style: TextStyle(fontSize: 10, color: NxColors.gray400)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar'))),
        NxButton(
          label: tr('Abrir WhatsApp'),
          tone: NxTone.emerald,
          height: 32,
          radius: 10,
          onTap: () async {
            final ok = await WhatsAppManager.open(widget.number, _text.text);
            if (!context.mounted) return;
            Navigator.pop(context);
            if (!ok) app.showToast(tr('No se pudo abrir WhatsApp'));
          },
        ),
      ],
    );
  }
}

/// Plantillas de WhatsApp (pestaña SIP).
class WhatsAppTemplatesPanel extends StatefulWidget {
  const WhatsAppTemplatesPanel({super.key});
  @override
  State<WhatsAppTemplatesPanel> createState() => _WhatsAppTemplatesPanelState();
}

class _WhatsAppTemplatesPanelState extends State<WhatsAppTemplatesPanel> {
  final app = AppController.I;
  late final List<TextEditingController> _ctl = [for (final t in app.whatsapp.templates) TextEditingController(text: t)];

  @override
  void dispose() {
    for (final c in _ctl) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NxPanel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Plantillas de WhatsApp'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(tr('{nombre} se sustituye por el nombre del cliente'), style: TextStyle(fontSize: 10, color: NxColors.gray500)),
              ]),
            ),
            Tactile(
              onTap: () => setState(() => _ctl.add(TextEditingController())),
              child: Text(tr('+ Añadir'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NxColors.goldDark)),
            ),
            const SizedBox(width: 10),
            NxButton(
              label: tr('Guardar'),
              tone: NxTone.dark,
              height: 28,
              radius: 10,
              fontSize: 11,
              onTap: () async {
                await app.whatsapp.save(_ctl.map((c) => c.text).toList());
                app.showToast(tr('Plantillas guardadas'));
              },
            ),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < _ctl.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: TextField(controller: _ctl[i], style: const TextStyle(fontSize: 11.5))),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: NxColors.gray400),
                  onPressed: () => setState(() => _ctl.removeAt(i).dispose()),
                ),
              ]),
            ),
        ]),
      );
}

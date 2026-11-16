import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/diagnostics.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ventana de diagnóstico: comprueba centralita, NAT, líneas, audio y cola, y permite
/// copiar el informe o lanzar la prueba de eco de FreePBX (*43).
class DiagnosticsDialog extends StatefulWidget {
  const DiagnosticsDialog({super.key});
  @override
  State<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<DiagnosticsDialog> {
  late Future<List<DiagItem>> _run = Diagnostics.run();

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    return AlertDialog(
      title: Text(tr('Diagnóstico')),
      content: SizedBox(
        width: 380,
        child: FutureBuilder<List<DiagItem>>(
          future: _run,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: NxColors.gold)),
                  const SizedBox(height: 12),
                  Text(tr('Comprobando centralita, líneas y audio…'), style: TextStyle(fontSize: 12, color: NxColors.gray500)),
                ]),
              );
            }
            final items = snap.data!;
            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                        switch (i.level) {
                          DiagLevel.ok => Icons.check_circle_rounded,
                          DiagLevel.warn => Icons.warning_amber_rounded,
                          DiagLevel.error => Icons.cancel_rounded,
                          DiagLevel.info => Icons.info_outline_rounded,
                        },
                        size: 17,
                        color: switch (i.level) {
                          DiagLevel.ok => NxColors.green600,
                          DiagLevel.warn => NxColors.amber,
                          DiagLevel.error => NxColors.red,
                          DiagLevel.info => NxColors.gray500,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NxColors.text)),
                          Text(i.detail, style: TextStyle(fontSize: 11, color: NxColors.gray600, height: 1.3)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final line = app.lines.lines.isEmpty ? null : app.lines.selectedLine;
            if (line == null || line.reg != RegState.registered) {
              app.showToast(tr('La línea seleccionada no está registrada'));
              return;
            }
            Navigator.pop(context);
            app.calls.makeCall(line, '*43');
            app.showToast(tr('Prueba de eco: habla y deberías oírte con un pequeño retardo'));
          },
          child: Text(tr('Prueba de eco (*43)')),
        ),
        TextButton(onPressed: () => setState(() => _run = Diagnostics.run()), child: Text(tr('Repetir'))),
        FutureBuilder<List<DiagItem>>(
          future: _run,
          builder: (context, snap) => TextButton(
            onPressed: !snap.hasData
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: Diagnostics.report(snap.data!)));
                    app.showToast(tr('Informe de diagnóstico copiado'));
                  },
            child: Text(tr('Copiar informe')),
          ),
        ),
        NxButton(label: tr('Cerrar'), tone: NxTone.dark, height: 32, radius: 10, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

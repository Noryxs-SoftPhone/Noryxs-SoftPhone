import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/i18n.dart';
import '../core/provisioning.dart';
import '../core/qr.dart';
import 'theme.dart';
import 'widgets.dart';

/// Panel "Configuración de puestos" (pestaña SIP): exportar este puesto o importar otro.
class ProvisioningPanel extends StatelessWidget {
  const ProvisioningPanel({super.key});

  @override
  Widget build(BuildContext context) => NxPanel(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Configuración de puestos'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(tr('Copia líneas, teclas BLF, cola, etiquetas y plantillas a otro puesto (cifrado con PIN)'),
                  style: TextStyle(fontSize: 10, color: NxColors.gray500)),
            ]),
          ),
          NxButton(label: tr('Importar'), tone: NxTone.white, height: 28, radius: 10, fontSize: 11, onTap: () => showImportDialog(context)),
          const SizedBox(width: 6),
          NxButton(label: tr('Exportar'), tone: NxTone.dark, height: 28, radius: 10, fontSize: 11, onTap: () => _export(context)),
        ]),
      );

  Future<void> _export(BuildContext context) async {
    final pin = await showDialog<String>(context: context, builder: (_) => const _PinDialog(confirm: true));
    if (pin == null || !context.mounted) return;
    final sealed = Provisioning.export(pin);
    if (sealed == null) {
      AppController.I.showToast(tr('No se pudo cifrar la configuración'));
      return;
    }
    await showDialog(context: context, builder: (_) => _ExportDialog(sealed: sealed));
  }
}

/// Abre la importación (también desde un enlace noryxs:provision o un QR).
Future<void> showImportDialog(BuildContext context, {String? sealed}) =>
    showDialog(context: context, builder: (_) => _ImportDialog(initial: sealed));

class _PinDialog extends StatefulWidget {
  const _PinDialog({this.confirm = false});
  final bool confirm;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _a = TextEditingController(), _b = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (_a.text.length < 4) return setState(() => _err = tr('El PIN debe tener al menos 4 cifras'));
    if (widget.confirm && _a.text != _b.text) return setState(() => _err = tr('Los PIN no coinciden'));
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('PIN del paquete')),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Protege las contraseñas. Lo pedirá el puesto que importe la configuración.'),
                style: TextStyle(fontSize: 11, color: NxColors.gray500)),
            const SizedBox(height: 10),
            TextField(
              controller: _a,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              decoration: InputDecoration(labelText: tr('PIN')),
              onSubmitted: (_) => widget.confirm ? null : _ok(),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _b,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                decoration: InputDecoration(labelText: tr('Repite el PIN')),
                onSubmitted: (_) => _ok(),
              ),
            ],
            if (_err != null) ...[const SizedBox(height: 8), Text(_err!, style: TextStyle(fontSize: 11, color: NxColors.red))],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar'))),
          NxButton(label: tr('Aceptar'), tone: NxTone.dark, height: 32, radius: 10, onTap: _ok),
        ],
      );
}

class _ExportDialog extends StatelessWidget {
  const _ExportDialog({required this.sealed});
  final String sealed;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final link = Provisioning.link(sealed);
    final qr = QrCode.encode(link);
    return AlertDialog(
      title: Text(tr('Configuración exportada')),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (qr != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: SizedBox.square(dimension: 230, child: CustomPaint(painter: _QrPainter(qr))),
            ),
            const SizedBox(height: 8),
            Text(tr('Escanéalo con la cámara del iPhone o envía el enlace o el fichero a otro puesto.'),
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: NxColors.gray500)),
          ] else
            Text(tr('La configuración es demasiado grande para un QR: usa el fichero o el enlace.'),
                style: TextStyle(fontSize: 11, color: NxColors.gray500)),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            app.showToast(tr('Enlace copiado'));
          },
          child: Text(tr('Copiar enlace')),
        ),
        TextButton(
          onPressed: () async {
            final path = await app.notifications.saveFile('puesto.${Provisioning.fileExt}', title: tr('Guardar configuración'));
            if (path == null) return;
            app.showToast(await Provisioning.saveTo(path, sealed) ? tr('Configuración guardada') : tr('No se pudo guardar el fichero'));
          },
          child: Text(tr('Guardar fichero…')),
        ),
        NxButton(label: tr('Cerrar'), tone: NxTone.dark, height: 32, radius: 10, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);
  final QrCode qr;
  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width / qr.size;
    final p = Paint()..color = const Color(0xFF111111);
    for (var y = 0; y < qr.size; y++) {
      for (var x = 0; x < qr.size; x++) {
        if (qr.get(x, y)) canvas.drawRect(Rect.fromLTWH(x * m, y * m, m + 0.3, m + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({this.initial});
  final String? initial;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _src = TextEditingController(text: widget.initial == null ? '' : tr('Paquete recibido por enlace'));
  final _pin = TextEditingController();
  String? _sealed;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sealed = widget.initial;
  }

  @override
  void dispose() {
    _src.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _fromFile() async {
    final path = await AppController.I.notifications.pickFile(title: tr('Fichero de configuración'));
    if (path == null) return;
    try {
      final p = Provisioning.extract(await File(path).readAsString());
      setState(() {
        _sealed = p;
        _src.text = p == null ? '' : path;
        _err = p == null ? tr('El fichero no contiene una configuración de NORYXS') : null;
      });
    } catch (_) {
      setState(() => _err = tr('No se pudo leer el fichero'));
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    var sealed = _sealed;
    final t = _src.text.trim();
    if (sealed == null && t.startsWith('http')) sealed = await Provisioning.download(t);
    sealed ??= Provisioning.extract(t);
    if (sealed == null) {
      setState(() {
        _busy = false;
        _err = tr('Pega un enlace o elige un fichero de configuración');
      });
      return;
    }
    final err = await Provisioning.apply(sealed, _pin.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _err = err;
      });
      return;
    }
    Navigator.pop(context);
    AppController.I.showToast(tr('Configuración importada · registrando líneas…'));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Importar configuración')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _src,
                  readOnly: _sealed != null && widget.initial != null,
                  onChanged: (_) => _sealed = null,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(labelText: tr('Enlace, dirección http o texto del paquete')),
                ),
              ),
              const SizedBox(width: 6),
              NxButton(label: tr('Fichero…'), tone: NxTone.white, height: 34, radius: 10, fontSize: 11, onTap: _fromFile),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              decoration: InputDecoration(labelText: tr('PIN')),
              onSubmitted: (_) => _import(),
            ),
            const SizedBox(height: 8),
            Text(tr('Sustituye las líneas, teclas y ajustes de cola de este puesto. No cambia nada en la centralita.'),
                style: TextStyle(fontSize: 10.5, color: NxColors.amberText)),
            if (_err != null) ...[const SizedBox(height: 8), Text(_err!, style: TextStyle(fontSize: 11, color: NxColors.red))],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar'))),
          NxButton(label: _busy ? tr('Importando…') : tr('Importar'), tone: NxTone.dark, height: 32, radius: 10, onTap: _busy ? null : _import),
        ],
      );
}

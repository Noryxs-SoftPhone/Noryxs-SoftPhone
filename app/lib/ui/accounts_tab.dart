import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/queue_manager.dart';
import '../core/sip_managers.dart';
import '../core/feature_managers.dart';
import '../core/models.dart';
import '../core/support_managers.dart';
import '../engine/sip_engine.dart';
import 'call_context.dart';
import 'theme.dart';
import 'widgets.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});
  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  final app = AppController.I;
  int _lineIndex = 0;
  bool _advanced = false;
  bool _saving = false;

  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _server = TextEditingController();
  final _port = TextEditingController();
  final _expires = TextEditingController();
  final _domain = TextEditingController();
  final _authUser = TextEditingController();
  final _proxy = TextEditingController();
  SipTransport _transport = SipTransport.udp;
  int _srtp = 0;
  bool _enabled = true;
  bool _hasPassword = false;
  String? _saveError;
  late List<MapEntry<String, bool>> _codecs;

  SipLine get _line => app.lines.lines[_lineIndex.clamp(0, app.lines.lines.length - 1)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final a = _line.account;
    _name.text = a.name;
    _user.text = a.username;
    _pass.clear();
    _server.text = a.server;
    _port.text = a.port.toString();
    _expires.text = a.expires.toString();
    _domain.text = a.domain;
    _authUser.text = a.authUser;
    _proxy.text = a.proxy;
    _transport = a.transport;
    _srtp = a.srtp;
    _enabled = a.enabled;
    _hasPassword = app.accounts.hasPassword(a);
    _codecs = List.of(app.audio.codecs);
  }

  @override
  void dispose() {
    for (final c in [_name, _user, _pass, _server, _port, _expires, _domain, _authUser, _proxy]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final a = _line.account
      ..name = _name.text.trim()
      ..username = _user.text.trim()
      ..server = _server.text.trim()
      ..port = int.tryParse(_port.text.trim()) ?? (_transport == SipTransport.tls ? 5061 : 5060)
      ..expires = (int.tryParse(_expires.text.trim()) ?? 300).clamp(60, 86400)
      ..domain = _domain.text.trim()
      ..authUser = _authUser.text.trim()
      ..proxy = _proxy.text.trim()
      ..transport = _transport
      ..srtp = _srtp
      ..enabled = _enabled;
    final pwd = _pass.text;
    _pass.clear();
    await app.audio.setCodecs(_codecs);
    final ok = await app.saveAccount(_line, password: pwd.isEmpty ? null : pwd);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = ok ? null : 'No se pudo guardar la contraseña en el Llavero de macOS';
      _hasPassword = app.accounts.hasPassword(a);
    });
  }

  Widget _field(String label, TextEditingController c,
      {bool mono = false, bool obscure = false, String? hint, List<TextInputFormatter>? fmt}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: NxColors.muted, fontWeight: FontWeight.w600, fontSize: 10.5)),
      const SizedBox(height: 4),
      TextField(
        controller: c,
        obscureText: obscure,
        enableSuggestions: !obscure,
        autocorrect: false,
        inputFormatters: fmt,
        style: TextStyle(fontFamily: mono ? kMono : null, fontSize: 12.5),
        decoration: InputDecoration(hintText: hint),
      ),
    ]);
  }

  Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: children[i]),
          ]
        ],
      );

  Widget _dropdown<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: NxColors.muted, fontWeight: FontWeight.w600, fontSize: 10.5)),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          isDense: true,
          iconSize: 18,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 12.5, color: NxColors.text),
          items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final lines = app.lines.lines;
    if (_lineIndex >= lines.length) _lineIndex = 0;
    final line = _line;
    final reg = line.reg;
    final regText = reg == RegState.registered
        ? 'Registrada (${line.regCode > 0 ? '${line.regCode} ' : ''}${line.regReason.isEmpty ? 'OK' : line.regReason})'
        : '${reg.label}${line.regReason.isNotEmpty ? ' · ${line.regCode > 0 ? '${line.regCode} ' : ''}${line.regReason}' : ''}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cuentas SIP • FreePBX', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Instancia PJSIP nativa • Almacenamiento seguro (Llavero del sistema)',
                  style: TextStyle(color: NxColors.faint, fontSize: 10.5)),
            ]),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<int>(
            tooltip: 'Seleccionar línea',
            onSelected: (i) async {
              if (i == -1) {
                await app.addLine();
                i = app.lines.lines.length - 1;
              }
              setState(() {
                _lineIndex = i;
                _load();
              });
            },
            itemBuilder: (_) => [
              for (final l in lines)
                PopupMenuItem(
                  value: l.index,
                  child: Row(children: [
                    StatusDot(regColor(l.reg)),
                    const SizedBox(width: 10),
                    Text('Línea ${l.number} (Ext. ${l.extension})'),
                  ]),
                ),
              if (lines.length < 8)
                const PopupMenuItem(value: -1, child: Text('+ Añadir línea', style: TextStyle(color: NxColors.gold))),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: NxColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NxColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Línea ${line.number} (Ext. ${line.extension})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.unfold_more, size: 14),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        NxPanel(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row([
              _field('Nombre identidad', _name, hint: 'Despacho Dirección'),
              _field('Usuario / Extensión SIP', _user, mono: true, hint: '201'),
            ]),
            const SizedBox(height: 10),
            _row([
              _field(_hasPassword ? 'Contraseña SIP (guardada en Llavero)' : 'Contraseña SIP', _pass,
                  obscure: true, hint: _hasPassword ? '••••••••••••' : 'Secreto de la extensión'),
              _field('Servidor FreePBX / IP', _server, mono: true, hint: 'pbx.empresa.local'),
            ]),
            const SizedBox(height: 10),
            _row([
              _field('Puerto', _port, mono: true, fmt: [FilteringTextInputFormatter.digitsOnly]),
              _dropdown<SipTransport>('Transporte', _transport, const [
                (SipTransport.udp, 'UDP'),
                (SipTransport.tcp, 'TCP'),
                (SipTransport.tls, 'TLS'),
              ], (v) {
                setState(() {
                  final p = int.tryParse(_port.text) ?? 0;
                  if (p == 0 || p == 5060 || p == 5061) _port.text = v == SipTransport.tls ? '5061' : '5060';
                  _transport = v;
                });
              }),
              _field('Expiración (s)', _expires, mono: true, fmt: [FilteringTextInputFormatter.digitsOnly]),
            ]),
            const SizedBox(height: 12),
            const Text('Códecs de audio habilitados (prioridad PJSIP, todas las líneas)',
                style: TextStyle(color: NxColors.muted, fontWeight: FontWeight.w600, fontSize: 10.5)),
            const SizedBox(height: 5),
            _CodecChips(
              codecs: _codecs,
              onChanged: (l) => setState(() => _codecs = l),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _advanced = !_advanced),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(_advanced ? Icons.expand_less : Icons.expand_more, color: NxColors.gold, size: 18),
                  const SizedBox(width: 2),
                  const Text('Opciones avanzadas', style: TextStyle(color: NxColors.gold, fontWeight: FontWeight.w600, fontSize: 11.5)),
                ]),
              ),
            ),
            if (_advanced) ...[
              const SizedBox(height: 4),
              _row([
                _field('Dominio SIP (opcional)', _domain, mono: true, hint: 'Igual que el servidor'),
                _field('Usuario de autenticación', _authUser, mono: true, hint: 'Igual que la extensión'),
              ]),
              const SizedBox(height: 10),
              _row([
                _field('Proxy de salida (opcional)', _proxy, mono: true, hint: 'host:puerto'),
                _dropdown<int>('SRTP (cifrado de audio)', _srtp, const [
                  (0, 'Desactivado'),
                  (1, 'Opcional'),
                  (2, 'Obligatorio'),
                ], (v) => setState(() => _srtp = v)),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Línea activada', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
              if (lines.length > 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: NxColors.red),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Eliminar línea ${line.number}'),
                    onPressed: () async {
                      await app.removeLine(line);
                      setState(() {
                        _lineIndex = 0;
                        _load();
                      });
                    },
                  ),
                ),
            ],
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_saveError!, style: const TextStyle(color: NxColors.red, fontWeight: FontWeight.w600, fontSize: 11.5)),
              ),
            const Divider(height: 18, color: NxColors.border),
            Row(children: [
              StatusDot(regColor(reg), size: 8),
              const SizedBox(width: 7),
              Expanded(
                child: Text(regText,
                    style: TextStyle(
                        color: reg == RegState.registered ? NxColors.greenText : regColor(reg),
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              SizedBox(
                width: 204,
                child: DarkButton(
                  height: 38,
                  fontSize: 12,
                  label: _saving ? 'Guardando…' : 'Guardar y Probar Registro',
                  onPressed: _saving ? null : _save,
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        const _BlfConfig(),
        const SizedBox(height: 14),
        const _QueueConfigPanel(),
        const SizedBox(height: 14),
        const _TagNamesPanel(),
      ],
    );
  }
}

/// Nombres de las 4 etiquetas de llamada (el color y el orden son fijos).
class _TagNamesPanel extends StatefulWidget {
  const _TagNamesPanel();
  @override
  State<_TagNamesPanel> createState() => _TagNamesPanelState();
}

class _TagNamesPanelState extends State<_TagNamesPanel> {
  final app = AppController.I;
  late final Map<String, TextEditingController> _ctl = {for (final t in app.history.tags) t.id: TextEditingController(text: t.label)};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = app.history.tags;
    return NxPanel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Etiquetas de llamada', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Se marcan con un toque en la llamada o el historial · notas y etiquetas cifradas en local',
                  style: TextStyle(fontSize: 10, color: NxColors.gray500)),
            ]),
          ),
          NxButton(
            label: 'Guardar',
            tone: NxTone.dark,
            height: 28,
            radius: 10,
            fontSize: 11,
            onTap: () async {
              await app.history.renameTags({for (final e in _ctl.entries) e.key: e.value.text});
              app.showToast('Nombres de etiquetas guardados');
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < tags.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (final t in tags.sublist(i, (i + 2).clamp(0, tags.length))) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: tagColors(t.color).dot)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _ctl[t.id],
                    maxLength: 20,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(counterText: ''),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Panel de cola: conexión AMI con usuario limitado (contraseña en el Llavero).
class _QueueConfigPanel extends StatefulWidget {
  const _QueueConfigPanel();
  @override
  State<_QueueConfigPanel> createState() => _QueueConfigPanelState();
}

class _QueueConfigPanelState extends State<_QueueConfigPanel> {
  final app = AppController.I;
  late final _host = TextEditingController(
      text: app.queue.config.host.isNotEmpty ? app.queue.config.host : (app.lines.lines.isNotEmpty ? app.lines.lines.first.account.server : ''));
  late final _port = TextEditingController(text: app.queue.config.port.toString());
  late final _user = TextEditingController(text: app.queue.config.user);
  late final _queues = TextEditingController(text: app.queue.config.queues.join(', '));
  final _pass = TextEditingController();
  late bool _enabled = app.queue.config.enabled;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _queues, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _f(String label, TextEditingController c, {bool obscure = false, bool mono = true, String? hint}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: NxColors.gray500, fontWeight: FontWeight.w500, fontSize: 10)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure,
          style: TextStyle(fontFamily: mono ? kMono : kSans, fontSize: 12),
          decoration: InputDecoration(hintText: hint),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final q = app.queue;
    final ok = q.state == AmiState.connected;
    return ListenableBuilder(
      listenable: q,
      builder: (context, _) => NxPanel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Panel de cola (FreePBX)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('AMI con usuario limitado · read=call,agent · write=call', style: TextStyle(fontSize: 10, color: NxColors.gray500)),
              ]),
            ),
            SizedBox(height: 26, child: FittedBox(child: Switch(value: _enabled, onChanged: (v) => setState(() => _enabled = v)))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 5, child: _f('Servidor AMI', _host, hint: '192.168.1.10')),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _f('Puerto', _port)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _f('Colas', _queues, hint: '400')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _f('Usuario AMI', _user)),
            const SizedBox(width: 8),
            Expanded(child: _f(q.hasPassword ? 'Contraseña (guardada en Llavero)' : 'Contraseña AMI', _pass, obscure: true, hint: q.hasPassword ? '••••••••' : '')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Led(ok ? NxColors.green : (q.state == AmiState.disabled ? NxColors.gray400 : NxColors.red500), size: 7),
            const SizedBox(width: 6),
            Expanded(
              child: Text(q.state == AmiState.disabled ? 'Desactivado' : q.stateText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ok ? NxColors.greenText : NxColors.gray600)),
            ),
            NxButton(
              label: 'Guardar y conectar',
              tone: NxTone.dark,
              height: 30,
              radius: 10,
              fontSize: 11,
              onTap: () async {
                q.config
                  ..enabled = _enabled
                  ..host = _host.text.trim()
                  ..port = int.tryParse(_port.text.trim()) ?? 5038
                  ..user = _user.text.trim().isEmpty ? 'noryxs' : _user.text.trim()
                  ..queues = _queues.text.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).toList();
                final p = _pass.text;
                _pass.clear();
                await q.save(password: p);
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Configuración de teclas BLF / órbitas de aparcamiento (máx. 6).
class _BlfConfig extends StatefulWidget {
  const _BlfConfig();
  @override
  State<_BlfConfig> createState() => _BlfConfigState();
}

class _BlfConfigState extends State<_BlfConfig> {
  final app = AppController.I;

  Future<void> _edit([BlfKey? k]) async {
    final ext = TextEditingController(text: k?.ext ?? '');
    final label = TextEditingController(text: k?.label ?? '');
    var park = k?.park ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(k == null ? 'Nueva tecla rápida' : 'Editar tecla rápida'),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: label, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre (ej. Recepción)')),
              const SizedBox(height: 10),
              TextField(
                controller: ext,
                style: const TextStyle(fontFamily: kMono),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: park ? 'Órbita (71–78)' : 'Extensión a supervisar'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: park,
                onChanged: (v) => setD(() => park = v),
                title: const Text('Órbita de aparcamiento (park)', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          actions: [
            if (k != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: NxColors.red),
                onPressed: () {
                  app.blf.keys.remove(k);
                  Navigator.pop(ctx, true);
                },
                child: const Text('Eliminar'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                if (ext.text.trim().isEmpty) return;
                final key = k ?? BlfKey(id: newId(), ext: '', label: '');
                key
                  ..ext = ext.text.trim()
                  ..label = label.text.trim().isEmpty ? (park ? 'Órbita ${ext.text.trim()}' : 'Ext. ${ext.text.trim()}') : label.text.trim()
                  ..park = park;
                if (k == null) app.blf.keys.add(key);
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await app.blf.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keys = app.blf.keys;
    return NxPanel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Teclas rápidas BLF y órbitas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text('SUBSCRIBE dialog · captura dirigida **ext · aparcamiento 70/71–78',
                  style: TextStyle(fontSize: 10, color: NxColors.gray500)),
            ]),
          ),
          if (keys.length < BlfManager.maxKeys) NxButton(label: '+ Añadir', tone: NxTone.white, height: 28, radius: 10, fontSize: 11, onTap: _edit),
        ]),
        const SizedBox(height: 10),
        if (keys.isEmpty) const Text('Sin teclas configuradas', style: TextStyle(fontSize: 11, color: NxColors.gray400)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in keys)
            Tactile(
              onTap: () => _edit(k),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: NxColors.border)),
                child: Text('${k.label} · ${k.park ? 'Slot' : 'Ext.'} ${k.ext}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _CodecChips extends StatelessWidget {
  const _CodecChips({required this.codecs, required this.onChanged});
  final List<MapEntry<String, bool>> codecs;
  final ValueChanged<List<MapEntry<String, bool>>> onChanged;

  @override
  Widget build(BuildContext context) {
    var n = 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < codecs.length; i++)
          Builder(builder: (_) {
            final c = codecs[i];
            final order = c.value ? ++n : null;
            return GestureDetector(
              onTap: () {
                final l = List.of(codecs);
                l[i] = MapEntry(c.key, !c.value);
                if (l.any((e) => e.value)) onChanged(l); // al menos un códec
              },
              onLongPress: i == 0
                  ? null
                  : () {
                      final l = List.of(codecs);
                      final x = l.removeAt(i);
                      l.insert(i - 1, x);
                      onChanged(l);
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.value ? NxColors.goldSoft.withValues(alpha: 0.55) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.value ? NxColors.goldBorder : NxColors.border),
                ),
                child: Text('${order != null ? '$order. ' : ''}${AudioDeviceManager.codecLabel(c.key)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        color: c.value ? NxColors.text : NxColors.faint,
                        decoration: c.value ? null : TextDecoration.lineThrough)),
              ),
            );
          }),
      ]),
      const SizedBox(height: 4),
      const Text('Toca para activar/desactivar · mantén pulsado para subir prioridad',
          style: TextStyle(color: NxColors.faint, fontSize: 9.5)),
    ]);
  }
}

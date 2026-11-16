import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/i18n.dart';
import '../core/support_managers.dart';
import '../core/ui_prefs.dart';
import 'about_section.dart';
import 'accounts_tab.dart';
import 'diagnostics_dialog.dart';
import 'provisioning_ui.dart';
import 'theme.dart';
import 'whatsapp_ui.dart';
import 'widgets.dart';

/// Pestaña "Ajustes": todas las opciones de la app, ordenadas por secciones.
/// Primero un menú; al tocar una sección se abre su página (con "‹ Ajustes" para volver).
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

enum _Section { lines, audio, alerts, appearance, blf, queue, tags, whatsapp, provisioning, updates, diagnostics, about }

class _SettingsTabState extends State<SettingsTab> {
  _Section? _open;

  ({IconData icon, String title, String subtitle}) _info(_Section s) => switch (s) {
        _Section.lines => (icon: Icons.dialpad_rounded, title: tr('Líneas SIP'), subtitle: tr('Extensiones, servidor, contraseñas y timbre de cada línea')),
        _Section.audio => (icon: Icons.graphic_eq_rounded, title: tr('Audio y tonos'), subtitle: tr('Micrófono, altavoz, volumen, tono de llamada y códecs')),
        _Section.alerts => (icon: Icons.notifications_none_rounded, title: tr('Avisos y escritorio'), subtitle: tr('Tarjeta flotante, inicio de sesión, atajos y enlaces tel:')),
        _Section.appearance => (icon: Icons.contrast_rounded, title: tr('Apariencia e idioma'), subtitle: tr('Tema claro u oscuro; castellano, catalán o inglés')),
        _Section.blf => (icon: Icons.grid_view_rounded, title: tr('Teclas BLF y aparcamiento'), subtitle: tr('Estado de compañeros, captura y órbitas')),
        _Section.queue => (icon: Icons.groups_2_outlined, title: tr('Cola de llamadas'), subtitle: tr('Panel «En espera» (AMI de FreePBX)')),
        _Section.tags => (icon: Icons.sell_outlined, title: tr('Etiquetas de llamada'), subtitle: tr('Nombres de las cuatro etiquetas')),
        _Section.whatsapp => (icon: Icons.chat_outlined, title: 'WhatsApp', subtitle: tr('Plantillas de mensajes')),
        _Section.provisioning => (icon: Icons.devices_other_rounded, title: tr('Configuración de puestos'), subtitle: tr('Copiar esta configuración a otros ordenadores')),
        _Section.updates => (icon: Icons.system_update_alt_rounded, title: tr('Actualizaciones'), subtitle: tr('Carpeta compartida con las versiones nuevas')),
        _Section.diagnostics => (icon: Icons.health_and_safety_outlined, title: tr('Diagnóstico'), subtitle: tr('Comprobar centralita, líneas, red y audio')),
        _Section.about => (icon: Icons.info_outline_rounded, title: tr('Acerca de'), subtitle: tr('Versión, compilación, autor y licencias')),
      };

  Widget _body(_Section s) => switch (s) {
        _Section.lines => const AccountsTab(),
        _Section.audio => const _AudioSection(),
        _Section.alerts => const _AlertsSection(),
        _Section.appearance => const _AppearanceSection(),
        _Section.blf => _padded(const BlfConfigPanel()),
        _Section.queue => _padded(const QueueConfigPanel()),
        _Section.tags => _padded(const TagNamesPanel()),
        _Section.whatsapp => _padded(const WhatsAppTemplatesPanel()),
        _Section.provisioning => _padded(const ProvisioningPanel()),
        _Section.updates => _padded(const UpdatesPanel()),
        _Section.diagnostics => _padded(const _DiagnosticsSection()),
        _Section.about => const AboutSection(),
      };

  static Widget _padded(Widget w) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [w]);

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      final i = _info(open);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 16, 4),
          child: Row(children: [
            Tactile(
              onTap: () => setState(() => _open = null),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chevron_left_rounded, size: 20, color: NxColors.goldDark),
                  Text(tr('Ajustes'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NxColors.goldDark)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(i.title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          ]),
        ),
        Expanded(child: _body(open)),
      ]);
    }
    Widget group(String title, List<_Section> items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: NxColors.gray400)),
          ),
          Container(
            decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: NxColors.border)),
            child: Column(children: [
              for (var k = 0; k < items.length; k++) ...[
                if (k > 0) Divider(height: 1, indent: 52, color: NxColors.border),
                _row(items[k]),
              ],
            ]),
          ),
        ]);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 16), children: [
      Text(tr('Ajustes'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      group(tr('Teléfono'), [_Section.lines, _Section.audio, _Section.alerts]),
      group(tr('Centralita'), [_Section.blf, _Section.queue]),
      group(tr('Llamadas'), [_Section.tags, _Section.whatsapp]),
      group(tr('App'), [_Section.appearance, _Section.provisioning, _Section.updates, _Section.diagnostics, _Section.about]),
    ]);
  }

  Widget _row(_Section s) {
    final i = _info(s);
    return Tactile(
      onTap: () => setState(() => _open = s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: NxColors.goldSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(i.icon, size: 17, color: NxColors.goldDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: NxColors.text)),
              Text(i.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: NxColors.gray500)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: NxColors.gray400),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.children, this.title});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: NxColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[Text(title!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 8)],
          ...children,
        ]),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged, {this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: NxColors.text)),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 10.5, color: NxColors.gray500, height: 1.3)),
            ]),
          ),
          SizedBox(height: 28, child: FittedBox(child: Switch(value: value, onChanged: onChanged))),
        ]),
      );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.options, required this.value, required this.onSelect});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onSelect;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          Tactile(
            onTap: () => onSelect(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: value == o.$1 ? NxColors.goldSoft : NxColors.card,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: value == o.$1 ? NxColors.gold : NxColors.border),
              ),
              child: Text(o.$2,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: value == o.$1 ? FontWeight.w700 : FontWeight.w500,
                      color: value == o.$1 ? NxColors.goldDark : NxColors.gray600)),
            ),
          ),
      ]);
}

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: NxColors.gray500)),
    );

// ---------------------------------------------------------------------------
// Secciones
// ---------------------------------------------------------------------------

class _AudioSection extends StatefulWidget {
  const _AudioSection();
  @override
  State<_AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<_AudioSection> {
  final app = AppController.I;
  late List<MapEntry<String, bool>> _codecs = List.of(app.audio.codecs);

  @override
  void initState() {
    super.initState();
    app.audio.refresh();
  }

  Widget _picker(String? value, List<String> names, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
        initialValue: names.contains(value) ? value : null,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: NxColors.card,
        style: TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('Predeterminado del sistema'))),
          for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final a = app.audio;
    final n = app.notifications;
    return ListenableBuilder(
      listenable: Listenable.merge([a, n]),
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        _Card(title: tr('Dispositivos'), children: [
          _label(tr('Micrófono')),
          _picker(a.captureName, a.inputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: v, playback: a.playbackName)),
          const SizedBox(height: 10),
          _label(tr('Altavoz / auricular')),
          _picker(a.playbackName, a.outputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: a.captureName, playback: v)),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(width: 72, child: Text(tr('Volumen'), style: TextStyle(fontSize: 11, color: NxColors.gray600))),
            Expanded(child: Slider(value: a.speakerVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(speaker: v))),
          ]),
          Row(children: [
            SizedBox(width: 72, child: Text(tr('Micrófono'), style: TextStyle(fontSize: 11, color: NxColors.gray600))),
            Expanded(child: Slider(value: a.micVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(mic: v))),
          ]),
          Text(tr('Cancelación de eco, reducción de ruido de fondo y volumen automático de la voz: siempre activados.'), style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
        ]),
        if (AppController.I.transcripts.available)
          _Card(title: tr('Transcripción de llamadas grabadas'), children: [
            Text(tr('Al colgar una llamada grabada se transcribe sola en este ordenador (el audio no sale del equipo). El texto aparece en el Historial y se puede buscar.'),
                style: TextStyle(fontSize: 10.5, color: NxColors.gray500)),
          ]),
        _Card(title: tr('Tono de llamada'), children: [
          _Choice<int>(
            options: [for (final e in NotificationManager.ringTones.entries) (e.key, e.value)],
            value: n.ringTone,
            onSelect: (t) {
              n.setPrefs(tone: t);
              n.previewTone(t);
            },
          ),
          const SizedBox(height: 6),
          Text(tr('Es el tono general; cada línea puede tener el suyo en Líneas SIP.'), style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
        ]),
        _Card(title: tr('Códecs'), children: [
          Text(tr('Toca para activar/desactivar · mantén pulsado para subir prioridad. Se aplican a todas las líneas.'),
              style: TextStyle(fontSize: 10.5, color: NxColors.gray500)),
          const SizedBox(height: 8),
          CodecChips(codecs: _codecs, onChanged: (l) => setState(() => _codecs = l)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: NxButton(
              label: tr('Guardar códecs'),
              tone: NxTone.dark,
              height: 30,
              radius: 10,
              fontSize: 11,
              onTap: () async {
                await a.setCodecs(_codecs);
                app.showToast(tr('Códecs guardados'));
              },
            ),
          ),
        ]),
      ]),
    );
  }
}

class _AlertsSection extends StatelessWidget {
  const _AlertsSection();
  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final n = app.notifications;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        if (Platform.isIOS)
          _Card(children: [
            Text(tr('NORYXS sigue conectada en segundo plano y avisa con una notificación. Si cierras la app deslizándola, no recibirá llamadas hasta que la abras.'),
                style: TextStyle(fontSize: 11.5, color: NxColors.gray600, height: 1.35)),
          ])
        else ...[
          _Card(title: tr('Llamadas entrantes'), children: [
            _Toggle(tr('Tarjeta flotante'), n.floatingCard, (v) => n.setPrefs(card: v),
                hint: tr('Aviso con Contestar / Silenciar / Rechazar cuando la ventana está minimizada o detrás de otra app')),
            if (Platform.isMacOS)
              _Toggle(tr('Notificación del sistema'), n.systemNotification, (v) => n.setPrefs(notify: v),
                  hint: tr('Además de la tarjeta, una notificación de macOS')),
          ]),
          _Card(title: tr('Escritorio'), children: [
            _Toggle(tr('Abrir al iniciar sesión'), n.launchAtLogin, (v) => n.setPrefs(login: v),
                hint: tr('Al cerrar la ventana sigue en {0} y recibiendo llamadas', [Platform.isMacOS ? tr('la barra de menús') : tr('la bandeja del sistema')])),
            if (!Platform.isLinux)
              _Toggle(tr('Atajos de teclado globales'), n.hotkeys, (v) => n.setPrefs(keys: v),
                  hint: Platform.isMacOS ? tr('⌃⌥A contestar · ⌃⌥H colgar · ⌃⌥M silenciar') : tr('Ctrl+Alt+A contestar · Ctrl+Alt+H colgar · Ctrl+Alt+M silenciar'))
            else
              Text(tr('Atajos: en Ajustes del sistema › Teclado crea atajos con las órdenes «noryxs-terminal --answer», «--hangup» y «--mute». El botón de los cascos contesta y cuelga.'),
                  style: TextStyle(fontSize: 10.5, color: NxColors.gray500, height: 1.35)),
          ]),
          _Card(title: tr('Clic para llamar'), children: [
            Text(tr('Llamar al pulsar números en el navegador, el correo u otras apps (enlaces tel: y sip:)'),
                style: TextStyle(fontSize: 11, color: NxColors.gray600, height: 1.3)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: NxButton(
                label: tr('Usar NORYXS'),
                tone: NxTone.dark,
                height: 30,
                radius: 10,
                fontSize: 11,
                onTap: () async {
                  final ok = await n.setDefaultDialer();
                  app.showToast(!ok
                      ? tr('No se pudo registrar NORYXS para los enlaces de teléfono')
                      : Platform.isWindows
                          ? tr('Elige NORYXS para TEL y SIP en la ventana de aplicaciones predeterminadas')
                          : tr('NORYXS abrirá los enlaces tel: y sip:'));
                },
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: UiPrefs.I,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          _Card(title: tr('Tema'), children: [
            _Choice<String>(
              options: [('light', tr('Claro')), ('dark', tr('Oscuro')), ('system', tr('Automático'))],
              value: UiPrefs.I.theme,
              onSelect: (t) => UiPrefs.I.set(theme: t),
            ),
            const SizedBox(height: 6),
            Text(tr('Automático sigue el modo claro u oscuro del sistema.'), style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
          ]),
          _Card(title: tr('Idioma'), children: [
            _Choice<String>(
              options: [('system', tr('Automático')), ('es', 'Español'), ('ca', 'Català'), ('en', 'English')],
              value: UiPrefs.I.lang,
              onSelect: (l) => UiPrefs.I.set(lang: l),
            ),
            const SizedBox(height: 6),
            Text(tr('Automático usa el idioma del sistema: catalán, castellano o inglés; con cualquier otro idioma, inglés.'), style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
          ]),
        ]),
      );
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection();
  @override
  Widget build(BuildContext context) => _Card(children: [
        Text(tr('Comprueba si la centralita responde, si hay NAT entre este equipo y la centralita, el registro de cada línea, los dispositivos de audio y el panel de cola. El informe se puede copiar para enviarlo a soporte.'),
            style: TextStyle(fontSize: 11.5, color: NxColors.gray600, height: 1.35)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: NxButton(
            label: tr('Ejecutar diagnóstico'),
            icon: Icons.play_arrow_rounded,
            tone: NxTone.dark,
            height: 32,
            radius: 10,
            fontSize: 11.5,
            onTap: () => showDialog(context: context, builder: (_) => const DiagnosticsDialog()),
          ),
        ),
      ]);
}

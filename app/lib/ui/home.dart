import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/feature_managers.dart';
import '../core/models.dart';
import 'accounts_tab.dart';
import 'call_context.dart';
import 'agenda_tab.dart';
import 'history_tab.dart';
import 'logo.dart';
import 'queue_panel.dart';
import 'terminal_tab.dart';
import 'theme.dart';
import 'voicemail_tab.dart';
import 'widgets.dart';

const _windowChannel = MethodChannel('noryxs/window');

/// Arrastrar la ventana desde la cabecera (la barra de título es transparente).
void startWindowDrag() {
  _windowChannel.invokeMethod('startDrag').catchError((_) => null);
}

enum NxTab { terminal, voicemail, contacts, history, settings }

const _ringToneLabels = {0: 'Trino', 2: 'Clásico', 3: 'Carillón'};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  NxTab _tab = NxTab.terminal;
  bool _fwdOpen = false;
  bool _audioOpen = false;

  // Panel lateral de cola: se abre solo cuando entra alguien; el usuario puede cerrarlo
  static const _panelWidth = 320.0;
  bool _panelDismissed = false;
  bool _panelPinned = false; // abierto a mano con el botón de la cabecera
  int _lastQueueCount = 0;
  bool? _windowPanelOpen;

  bool get _panelVisible {
    final q = app.queue;
    if (!q.config.enabled) return false;
    final n = q.callers.length;
    if (n > _lastQueueCount) _panelDismissed = false; // nueva llamada en cola: reabrir
    _lastQueueCount = n;
    return _panelPinned || (n > 0 && !_panelDismissed);
  }

  /// Botón de la cabecera: mostrar / ocultar el panel de cola en cualquier momento.
  void _toggleQueuePanel() {
    final visible = _panelVisible;
    setState(() {
      if (visible) {
        _panelPinned = false;
        _panelDismissed = true;
      } else {
        _panelPinned = true;
        _panelDismissed = false;
      }
    });
  }

  void _syncWindow(bool open) {
    if (_windowPanelOpen == open) return;
    _windowPanelOpen = open;
    _windowChannel.invokeMethod('setSidePanel', {'open': open, 'width': _panelWidth}).catchError((_) => null);
  }
  final _terminalKey = GlobalKey<TerminalTabState>();
  final app = AppController.I;

  void go(NxTab t) => setState(() => _tab = t);

  /// Llamar desde agenda/historial/buzón: vuelve al terminal.
  void callNumber(String number, {SipLine? line}) {
    if (line != null) app.lines.select(line.index);
    setState(() => _tab = NxTab.terminal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _terminalKey.currentState?.dialAndCall(number));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // En iPhone: respetar notch / Dynamic Island y la barra de inicio
      body: SafeArea(
        top: Platform.isIOS,
        bottom: Platform.isIOS,
        left: false,
        right: false,
        child: ListenableBuilder(
        listenable: app.all,
        builder: (context, _) {
          final ringing = app.calls.liveCalls.where((c) => c.state == CallState.incoming).firstOrNull;
          final panel = _panelVisible;
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindow(panel));
          return LayoutBuilder(builder: (context, cons) {
            final fits = cons.maxWidth >= 440 + _panelWidth;
            void close() => setState(() {
                  _panelDismissed = true;
                  _panelPinned = false;
                });
            // En macOS la ventana siempre se ensancha (animación nativa): mientras tanto no se superpone.
            if (fits || !panel || Platform.isMacOS) {
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _phone(ringing, panel)),
                if (panel && fits) SizedBox(width: _panelWidth, child: QueuePanel(onClose: close)),
              ]);
            }
            // La ventana no se ha podido ensanchar (maximizada, en mosaico, Wayland, móvil…):
            // el panel se abre por encima del terminal, desde la derecha.
            final w = cons.maxWidth < _panelWidth + 40 ? cons.maxWidth : _panelWidth;
            return Stack(children: [
              Positioned.fill(child: _phone(ringing, panel)),
              Positioned.fill(child: GestureDetector(onTap: close, child: const ColoredBox(color: Color(0x33000000)))),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: w,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Transform.translate(offset: Offset(w * t, 0), child: child),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24)]),
                    child: QueuePanel(onClose: close),
                  ),
                ),
              ),
            ]);
          });
        },
      ),
      ),
    );
  }

  Widget _phone(CallSession? ringing, bool panel) {
          return Stack(children: [
            Column(children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: ringing == null ? const SizedBox(width: double.infinity) : RingingDrawer(call: ringing),
              ),
              _Header(
                topInset: ringing == null,
                onDnd: () async => app.showToast(await app.features.setDnd(!app.features.dnd)),
                onForward: () => setState(() {
                  _fwdOpen = !_fwdOpen;
                  _audioOpen = false;
                }),
                onVoicemail: () => go(NxTab.voicemail),
                queuePanelOpen: panel,
                onQueue: app.queue.config.enabled ? _toggleQueuePanel : null,
                onAudio: () => setState(() {
                  _audioOpen = !_audioOpen;
                  _fwdOpen = false;
                }),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _fwdOpen
                    ? _ForwardDrawer(onClose: () => setState(() => _fwdOpen = false))
                    : _audioOpen
                        ? _AudioDrawer(onClose: () => setState(() => _audioOpen = false))
                        : const SizedBox(width: double.infinity),
              ),
              if (app.startupError != null)
                Container(
                  width: double.infinity,
                  color: NxColors.redSoft,
                  padding: const EdgeInsets.all(8),
                  child: Text(app.startupError!, style: const TextStyle(color: NxColors.redText, fontWeight: FontWeight.w600, fontSize: 11)),
                ),
              Expanded(
                child: IndexedStack(index: _tab.index, children: [
                  TerminalTab(key: _terminalKey),
                  VoicemailTab(onCall: callNumber),
                  AgendaTab(onCall: (n) => callNumber(n)),
                  HistoryTab(onCall: callNumber),
                  const AccountsTab(),
                ]),
              ),
              _BottomNav(tab: _tab, onTap: go, mwi: app.voicemail.totalNew > 0),
            ]),
            // Aviso breve sobre la navegación
            Positioned(
              left: 16,
              right: 16,
              bottom: 64,
              child: IgnorePointer(
                child: ValueListenableBuilder<String?>(
                  valueListenable: app.toast,
                  builder: (_, msg, _) => AnimatedOpacity(
                    opacity: msg == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: NxColors.dark,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: Row(children: [
                        Expanded(child: Text(msg ?? '', style: const TextStyle(color: Colors.white, fontSize: 12))),
                        const SizedBox(width: 8),
                        const Text('SIP/2.0', style: TextStyle(color: NxColors.gold, fontFamily: kMono, fontSize: 10)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
  }
}

// ---------------------------------------------------------------------------
// Franja de llamada entrante integrada (contexto A: ventana abierta)
// ---------------------------------------------------------------------------

class RingingDrawer extends StatelessWidget {
  const RingingDrawer({super.key, required this.call});
  final CallSession call;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final line = app.calls.lineOf(call);
    final active = app.calls.liveCalls.where((x) => x.callId != call.callId && x.state == CallState.active).firstOrNull;
    final activeLine = active == null ? null : app.calls.lineOf(active);
    final more = app.calls.liveCalls.where((x) => x.callId != call.callId && x.state == CallState.incoming).length;
    return GestureDetector(
      onPanStart: (_) => startWindowDrag(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, Platform.isMacOS ? 30 : 14, 20, 14),
        decoration: BoxDecoration(
          color: NxColors.dark,
          border: Border(bottom: BorderSide(color: NxColors.gold.withValues(alpha: 0.5))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Led(NxColors.gold, size: 9, pulse: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'LLAMADA ENTRANTE • ${line?.label ?? 'IP DIRECTA'}${line != null ? ' (EXT. ${line.extension})' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NxColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
            Text(more > 0 ? '+$more EN COLA' : 'SIP INVITE',
                style: TextStyle(color: more > 0 ? NxColors.gold : NxColors.gray400, fontFamily: kMono, fontSize: 10)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(call.displayName.isEmpty ? 'Número oculto' : call.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                if (call.displayName != call.remoteNumber && call.remoteNumber.isNotEmpty)
                  Text(call.remoteNumber, style: const TextStyle(color: Color(0xFFD1D5DB), fontFamily: kMono, fontSize: 12)),
                CallerContext(number: call.remoteNumber, dark: true),
              ]),
            ),
            if (active != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Multi-línea activa', style: TextStyle(color: NxColors.gold, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('Retendrá ${activeLine?.label.replaceFirst('LÍNEA', 'Línea') ?? active.displayName}',
                      style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 10)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 6,
              child: _DrawerBtn(label: 'Contestar', icon: Icons.call, bg: NxColors.green, fg: Colors.white, onTap: () => app.calls.answer(call)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _DrawerBtn(
                label: call.ringSilenced ? 'Silenciado' : 'Silenciar',
                icon: Icons.volume_off_outlined,
                bg: Colors.white.withValues(alpha: 0.10),
                fg: const Color(0xFFE5E7EB),
                onTap: call.ringSilenced ? null : () => app.calls.silenceRing(call),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _DrawerBtn(
                label: 'Rechazar',
                bg: NxColors.red500.withValues(alpha: 0.20),
                fg: const Color(0xFFFECACA),
                border: const Color(0x4DF87171),
                onTap: () => app.calls.reject(call),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DrawerBtn extends StatelessWidget {
  const _DrawerBtn({required this.label, required this.bg, required this.fg, required this.onTap, this.icon, this.border});
  final String label;
  final IconData? icon;
  final Color bg, fg;
  final Color? border;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tactile(
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border == null ? null : Border.all(color: border!),
          ),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
            Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Cabecera: emblema, DND, desvío, buzón y audio
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.topInset,
    required this.onDnd,
    required this.onForward,
    required this.onVoicemail,
    required this.onAudio,
    this.onQueue,
    this.queuePanelOpen = false,
  });
  final bool topInset;
  final VoidCallback onDnd, onForward, onVoicemail, onAudio;
  final VoidCallback? onQueue; // null = panel de cola desactivado → sin botón
  final bool queuePanelOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final f = app.features;
    final mwi = app.voicemail.totalNew;
    final fwdOn = f.forwardMode != ForwardMode.off;
    // En macOS los botones de ventana ocupan la esquina superior izquierda
    final macInset = Platform.isMacOS && topInset;
    return GestureDetector(
      onPanStart: (_) => startWindowDrag(),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, macInset ? 34 : 12, 16, 11), // franja superior para los botones de ventana de macOS
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: NxColors.border))),
        child: Row(children: [
          const NoryxsLogo(size: 30),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('NORYXS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                SizedBox(width: 6),
                Pill('SIP', fg: NxColors.goldDark, bg: NxColors.goldSoft, border: NxColors.goldBorder, size: 8.5, compact: true),
              ]),
              Text('Virtual IP Terminal • PJSIP',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: NxColors.muted, fontWeight: FontWeight.w500)),
            ]),
          ),
          _HeaderChip(
            tooltip: 'No molestar (SIP 486 + FreePBX *78/*79)',
            onTap: onDnd,
            bg: f.dnd ? NxColors.redSoft : NxColors.surface,
            border: f.dnd ? NxColors.redBorder : NxColors.border,
            child: Row(children: [
              Led(f.dnd ? NxColors.red500 : NxColors.gray400, size: 6),
              const SizedBox(width: 4),
              Text('DND',
                  style: TextStyle(fontSize: 11, fontWeight: f.dnd ? FontWeight.w700 : FontWeight.w600, color: f.dnd ? NxColors.redText : NxColors.gray600)),
            ]),
          ),
          const SizedBox(width: 4),
          _HeaderChip(
            tooltip: 'Desvío de llamadas (FreePBX *72 / *90 / *52)',
            onTap: onForward,
            bg: fwdOn ? NxColors.goldSoft : NxColors.surface,
            border: fwdOn ? NxColors.gold : NxColors.border,
            child: Row(children: [
              Icon(Icons.turn_right_rounded, size: 14, color: fwdOn ? NxColors.goldDark : NxColors.gray600),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 70),
                child: Text(fwdOn ? '→ ${f.forwardTarget}' : 'Desvío',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: fwdOn ? FontWeight.w700 : FontWeight.w600,
                        color: fwdOn ? NxColors.goldDark : NxColors.gray600,
                        fontFamily: fwdOn ? kMono : kSans)),
              ),
            ]),
          ),
          const SizedBox(width: 4),
          Stack(clipBehavior: Clip.none, children: [
            _HeaderChip(
              tooltip: 'Buzón de voz (MWI)',
              onTap: onVoicemail,
              square: true,
              child: const Icon(Icons.voicemail_rounded, size: 16, color: NxColors.gray600),
            ),
            if (mwi > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: NxColors.gold,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 2)],
                  ),
                  alignment: Alignment.center,
                  child: Text('$mwi', style: const TextStyle(color: Colors.white, fontFamily: kMono, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
          if (onQueue != null) ...[
            const SizedBox(width: 4),
            Stack(clipBehavior: Clip.none, children: [
              _HeaderChip(
                tooltip: queuePanelOpen ? 'Ocultar la cola de llamadas' : 'Mostrar la cola de llamadas',
                onTap: onQueue!,
                square: true,
                bg: queuePanelOpen ? NxColors.goldSoft : NxColors.surface,
                border: queuePanelOpen ? NxColors.gold : NxColors.border,
                child: Icon(Icons.groups_2_outlined, size: 16, color: queuePanelOpen ? NxColors.goldDark : NxColors.gray600),
              ),
              if (app.queue.callers.isNotEmpty)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: NxColors.gold, borderRadius: BorderRadius.circular(99)),
                    alignment: Alignment.center,
                    child: Text('${app.queue.callers.length}',
                        style: const TextStyle(color: Colors.white, fontFamily: kMono, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ],
          const SizedBox(width: 4),
          _HeaderChip(
            tooltip: 'Dispositivos de audio, volumen y avisos',
            onTap: onAudio,
            square: true,
            child: const Icon(Icons.headset_mic_outlined, size: 16, color: NxColors.gray600),
          ),
        ]),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.child, required this.onTap, this.bg = NxColors.surface, this.border = NxColors.border, this.square = false, this.tooltip});
  final Widget child;
  final VoidCallback onTap;
  final Color bg, border;
  final bool square;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Tactile(
        onTap: onTap,
        tooltip: tooltip,
        child: Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: square ? 7 : 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          alignment: Alignment.center,
          child: child,
        ),
      );
}

// ---------------------------------------------------------------------------
// Panel de desvío
// ---------------------------------------------------------------------------

class _ForwardDrawer extends StatefulWidget {
  const _ForwardDrawer({required this.onClose});
  final VoidCallback onClose;
  @override
  State<_ForwardDrawer> createState() => _ForwardDrawerState();
}

class _ForwardDrawerState extends State<_ForwardDrawer> {
  final app = AppController.I;
  late ForwardMode _mode = app.features.forwardMode;
  late final _target = TextEditingController(text: app.features.forwardTarget);

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = app.lines.selectedLine;
    return _Drawer(
      title: 'Desvío de llamadas (FreePBX)',
      onClose: widget.onClose,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Labeled(
              'Modo de desvío',
              DropdownButtonFormField<ForwardMode>(
                initialValue: _mode,
                isDense: true,
                isExpanded: true,
                iconSize: 16,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Colors.white,
                style: const TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
                items: [for (final m in ForwardMode.values) DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _mode = v ?? ForwardMode.off),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Labeled(
              'Destino (ext. o móvil)',
              TextField(
                controller: _target,
                style: const TextStyle(fontFamily: kMono, fontSize: 12),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+*# ]'))],
                decoration: const InputDecoration(hintText: 'Ej. 205 o +34 600…'),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
                'Se aplica en la centralita a ${line.label.replaceFirst('LÍNEA', 'Línea')} (ext. ${line.extension}). Funciona aunque el ordenador esté apagado.',
                style: const TextStyle(fontSize: 10, color: NxColors.gray400)),
          ),
          const SizedBox(width: 8),
          NxButton(
            label: 'Aplicar desvío',
            tone: NxTone.dark,
            height: 30,
            radius: 12,
            fontSize: 11,
            onTap: () async {
              final err = await app.features.setForward(_mode, _target.text, line);
              if (err != null) {
                app.showToast(err);
                return;
              }
              app.showToast(_mode == ForwardMode.off ? 'Desvío desactivado' : 'Desvío activo hacia ${app.features.forwardTarget}');
              widget.onClose();
            },
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel de audio y avisos
// ---------------------------------------------------------------------------

class _AudioDrawer extends StatefulWidget {
  const _AudioDrawer({required this.onClose});
  final VoidCallback onClose;
  @override
  State<_AudioDrawer> createState() => _AudioDrawerState();
}

class _AudioDrawerState extends State<_AudioDrawer> {
  final app = AppController.I;

  @override
  void initState() {
    super.initState();
    app.audio.refresh(); // detectar auriculares USB/Bluetooth conectados en caliente
  }

  Widget _picker(String? value, List<String> names, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
        initialValue: names.contains(value) ? value : null,
        isDense: true,
        isExpanded: true,
        iconSize: 16,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: Colors.white,
        style: const TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
        items: [
          const DropdownMenuItem(value: null, child: Text('Predeterminado del sistema')),
          for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final a = app.audio;
    final n = app.notifications;
    return _Drawer(
      title: 'Dispositivos de audio · ${Platform.isMacOS ? 'CoreAudio' : Platform.isWindows ? 'WASAPI' : 'ALSA/PulseAudio'}',
      onClose: widget.onClose,
      children: [
        Row(children: [
          Expanded(child: _Labeled('Micrófono', _picker(a.captureName, a.inputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: v, playback: a.playbackName)))),
          const SizedBox(width: 8),
          Expanded(
              child: _Labeled('Altavoz / auricular', _picker(a.playbackName, a.outputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: a.captureName, playback: v)))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Text('Volumen', style: TextStyle(fontSize: 10, color: NxColors.gray500)),
          Expanded(child: Slider(value: a.speakerVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(speaker: v))),
          const Text('Mic', style: TextStyle(fontSize: 10, color: NxColors.gray500)),
          Expanded(child: Slider(value: a.micVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(mic: v))),
          const Pill('AEC ON', bg: Colors.white, border: NxColors.border, mono: true, size: 9.5),
        ]),
        const Divider(height: 12, color: NxColors.border),
        Row(children: [
          const Text('Tono de llamada', style: TextStyle(fontSize: 10, color: NxColors.gray500, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          for (final e in _ringToneLabels.entries) ...[
            Tactile(
              onTap: () {
                n.setPrefs(tone: e.key);
                n.previewTone(e.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: n.ringTone == e.key ? NxColors.goldSoft : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: n.ringTone == e.key ? NxColors.gold : NxColors.border),
                ),
                child: Text(e.value,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: n.ringTone == e.key ? FontWeight.w700 : FontWeight.w500,
                        color: n.ringTone == e.key ? NxColors.goldDark : NxColors.gray600)),
              ),
            ),
            const SizedBox(width: 5),
          ],
        ]),
        const SizedBox(height: 4),
        if (!Platform.isIOS) ...[
          Row(children: [
            Expanded(child: _Toggle('Tarjeta flotante si está minimizada', n.floatingCard, (v) => n.setPrefs(card: v))),
            if (Platform.isMacOS) Expanded(child: _Toggle('Notificación del sistema', n.systemNotification, (v) => n.setPrefs(notify: v))),
          ]),
          _Toggle('Abrir NORYXS al iniciar sesión (sigue en ${Platform.isMacOS ? 'la barra de menús' : 'la bandeja del sistema'} al cerrar la ventana)', n.launchAtLogin, (v) => n.setPrefs(login: v)),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('NORYXS sigue conectada en segundo plano y avisa con una notificación. Si cierras la app deslizándola, no recibirá llamadas hasta que la abras.',
                style: TextStyle(fontSize: 10.5, color: NxColors.gray500, height: 1.35)),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(height: 26, child: FittedBox(child: Switch(value: value, onChanged: onChanged))),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 10.5, color: NxColors.gray600))),
      ]);
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.title, required this.onClose, required this.children});
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: const BoxDecoration(color: NxColors.surface, border: Border(bottom: BorderSide(color: NxColors.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Tactile(onTap: onClose, child: const Text('Cerrar', style: TextStyle(fontSize: 11.5, color: NxColors.gray400, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: NxColors.gray500, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        child,
      ]);
}

// ---------------------------------------------------------------------------
// Navegación inferior
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onTap, required this.mwi});
  final NxTab tab;
  final ValueChanged<NxTab> onTap;
  final bool mwi;

  @override
  Widget build(BuildContext context) {
    const items = [
      (NxTab.terminal, Icons.smartphone_rounded, 'Terminal'),
      (NxTab.voicemail, Icons.voicemail_rounded, 'Buzón'),
      (NxTab.contacts, Icons.people_outline_rounded, 'Contactos'),
      (NxTab.history, Icons.schedule_rounded, 'Historial'),
      (NxTab.settings, Icons.settings_outlined, 'SIP'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: NxColors.surface, border: Border(top: BorderSide(color: NxColors.border))),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tactile(
                onTap: () => onTap(it.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: tab == it.$1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tab == it.$1 ? NxColors.border : Colors.transparent),
                    boxShadow: tab == it.$1 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1))] : null,
                  ),
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(it.$2,
                          size: 16,
                          color: it.$1 == NxTab.terminal && tab == it.$1
                              ? NxColors.goldDark
                              : tab == it.$1
                                  ? NxColors.text
                                  : NxColors.gray500),
                      const SizedBox(height: 2),
                      Text(it.$3,
                          style: TextStyle(
                              fontSize: 11, fontWeight: tab == it.$1 ? FontWeight.w600 : FontWeight.w500, color: tab == it.$1 ? NxColors.text : NxColors.gray500)),
                    ]),
                    if (it.$1 == NxTab.voicemail && mwi) const Positioned(top: 0, right: 14, child: Led(NxColors.gold, size: 6)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

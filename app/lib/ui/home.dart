// Los parámetros con nombre no pueden ser privados: los colores opcionales se guardan en campos privados.
// ignore_for_file: prefer_initializing_formals
import 'dart:io';
import '../core/i18n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/feature_managers.dart';
import '../core/models.dart';
import 'call_context.dart';
import 'agenda_tab.dart';
import 'history_tab.dart';
import 'logo.dart';
import 'nav_icons.dart';
import 'provisioning_ui.dart';
import 'settings_tab.dart';
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


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // Transición suave al cambiar de pestaña
  late final AnimationController _tabAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);

  @override
  void initState() {
    super.initState();
    // Enlace noryxs:provision (QR o correo): abrir la importación
    AppController.I.onProvisionLink = (p) {
      final ctx = AppController.navigatorKey.currentContext;
      if (ctx != null) showImportDialog(ctx, sealed: p);
    };
  }

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

  @override
  void dispose() {
    _tabAnim.dispose();
    super.dispose();
  }

  NxTab get tab => _tab;

  void go(NxTab t) {
    if (t != _tab) _tabAnim.forward(from: 0);
    setState(() => _tab = t);
    // De vuelta al terminal: el teclado del ordenador escribe en el marcador
    if (t == NxTab.terminal) WidgetsBinding.instance.addPostFrameCallback((_) => _terminalKey.currentState?.grabKeyboard());
  }

  /// Llamar desde agenda/historial/buzón: vuelve al terminal.
  void callNumber(String number, {SipLine? line}) {
    if (line != null) app.lines.select(line.index);
    setState(() => _tab = NxTab.terminal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _terminalKey.currentState?.dialAndCall(number));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // repintar todo al cambiar entre modo claro y oscuro
    return Scaffold(
      backgroundColor: NxColors.background,
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
              if (app.updates.availableVersion != null) const _UpdateBanner(),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _fwdOpen
                    ? _ForwardDrawer(key: ValueKey(app.lines.lines.isEmpty ? '' : app.lines.selectedLine.account.id), onClose: () => setState(() => _fwdOpen = false))
                    : _audioOpen
                        ? _AudioDrawer(onClose: () => setState(() => _audioOpen = false))
                        : const SizedBox(width: double.infinity),
              ),
              if (app.startupError != null)
                Container(
                  width: double.infinity,
                  color: NxColors.redSoft,
                  padding: const EdgeInsets.all(8),
                  child: Text(app.startupError!, style: TextStyle(color: NxColors.redText, fontWeight: FontWeight.w600, fontSize: 11)),
                ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _tabAnim,
                  builder: (context, child) {
                    final v = Curves.easeOutCubic.transform(_tabAnim.value);
                    return Opacity(opacity: 0.35 + 0.65 * v, child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child));
                  },
                  child: IndexedStack(index: _tab.index, children: [
                  TerminalTab(key: _terminalKey),
                  VoicemailTab(onCall: callNumber),
                  AgendaTab(onCall: (n) => callNumber(n)),
                  HistoryTab(onCall: callNumber),
                  const SettingsTab(),
                ]),
                )
              ),
              _BottomNav(tab: _tab, onTap: go, mwi: app.voicemail.totalNew > 0, pending: app.history.pendingMissed.length),
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
                        Text('SIP/2.0', style: TextStyle(color: NxColors.gold, fontFamily: kMono, fontSize: 10)),
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
            Led(NxColors.gold, size: 9, pulse: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('LLAMADA ENTRANTE • {0}{1}', [line?.label ?? 'IP DIRECTA', line != null ? ' (EXT. ${line.extension})' : '']),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: NxColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
            Text(more > 0 ? tr('+{0} EN COLA', [more]) : tr('SIP INVITE'),
                style: TextStyle(color: more > 0 ? NxColors.gold : NxColors.gray400, fontFamily: kMono, fontSize: 10)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(call.displayName.isEmpty ? tr('Número oculto') : call.displayName,
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
                  Text(tr('Multi-línea activa'), style: TextStyle(color: NxColors.gold, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text(tr('Retendrá {0}', [activeLine?.label.replaceFirst('LÍNEA', 'Línea') ?? active.displayName]),
                      style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 10)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 6,
              child: _DrawerBtn(label: tr('Contestar'), icon: Icons.call, bg: NxColors.green, fg: Colors.white, onTap: () => app.calls.answer(call)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _DrawerBtn(
                label: call.ringSilenced ? tr('Silenciado') : tr('Silenciar'),
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
                label: tr('Rechazar'),
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
        decoration: BoxDecoration(color: NxColors.card, border: Border(bottom: BorderSide(color: NxColors.border))),
        child: Row(children: [
          const NoryxsLogo(size: 30),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('NORYXS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                SizedBox(width: 6),
                Pill('SIP', fg: NxColors.goldDark, bg: NxColors.goldSoft, border: NxColors.goldBorder, size: 8.5, compact: true),
              ]),
              Text(tr('Virtual IP Terminal • PJSIP'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: NxColors.muted, fontWeight: FontWeight.w500)),
            ]),
          ),
          _HeaderChip(
            tooltip: tr('No molestar de la línea seleccionada (SIP 486 + FreePBX *78/*79)'),
            onTap: onDnd,
            bg: f.dnd ? NxColors.redSoft : NxColors.surface,
            border: f.dnd ? NxColors.redBorder : NxColors.border,
            child: Row(children: [
              NavIcon(NavGlyph.moon, size: 15, color: f.dnd ? NxColors.redText : NxColors.gray600, fill: f.dnd ? NxColors.red.withValues(alpha: 0.15) : null),
              const SizedBox(width: 4),
              Text('DND',
                  style: TextStyle(fontSize: 11, fontWeight: f.dnd ? FontWeight.w700 : FontWeight.w600, color: f.dnd ? NxColors.redText : NxColors.gray600)),
            ]),
          ),
          const SizedBox(width: 4),
          _HeaderChip(
            tooltip: tr('Desvío de la línea seleccionada (FreePBX *72 / *90 / *52)'),
            onTap: onForward,
            bg: fwdOn ? NxColors.goldSoft : NxColors.surface,
            border: fwdOn ? NxColors.gold : NxColors.border,
            child: Row(children: [
              NavIcon(NavGlyph.forward, size: 15, color: fwdOn ? NxColors.goldDark : NxColors.gray600),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 70),
                child: Text(fwdOn ? '→ ${f.forwardTarget}' : tr('Desvío'),
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
              tooltip: tr('Buzón de voz (MWI)'),
              onTap: onVoicemail,
              square: true,
              child: NavIcon(NavGlyph.voicemail, size: 17, color: NxColors.gray600),
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
                tooltip: queuePanelOpen ? tr('Ocultar la cola de llamadas') : tr('Mostrar la cola de llamadas'),
                onTap: onQueue!,
                square: true,
                bg: queuePanelOpen ? NxColors.goldSoft : NxColors.surface,
                border: queuePanelOpen ? NxColors.gold : NxColors.border,
                child: NavIcon(NavGlyph.queue, size: 17, color: queuePanelOpen ? NxColors.goldDark : NxColors.gray600),
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
            tooltip: tr('Dispositivos de audio, volumen y avisos'),
            onTap: onAudio,
            square: true,
            child: NavIcon(NavGlyph.headset, size: 17, color: NxColors.gray600),
          ),
        ]),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.child, required this.onTap, Color? bg, Color? border, this.square = false, this.tooltip})
      : _bg = bg,
        _border = border;
  final Widget child;
  final VoidCallback onTap;
  final Color? _bg, _border;
  Color get bg => _bg ?? NxColors.surface;
  Color get border => _border ?? NxColors.border;
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
  const _ForwardDrawer({super.key, required this.onClose});
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
      title: tr('Desvío de llamadas (FreePBX)'),
      onClose: widget.onClose,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Labeled(
              tr('Modo de desvío'),
              DropdownButtonFormField<ForwardMode>(
                initialValue: _mode,
                isDense: true,
                isExpanded: true,
                iconSize: 16,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: NxColors.card,
                style: TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
                items: [for (final m in ForwardMode.values) DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _mode = v ?? ForwardMode.off),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Labeled(
              tr('Destino (ext. o móvil)'),
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
                tr('Se aplica en la centralita a {0} (ext. {1}). Funciona aunque el ordenador esté apagado.', [line.label.replaceFirst('LÍNEA', 'Línea'), line.extension]),
                style: TextStyle(fontSize: 10, color: NxColors.gray400)),
          ),
          const SizedBox(width: 8),
          NxButton(
            label: tr('Aplicar desvío'),
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
              app.showToast(_mode == ForwardMode.off ? tr('Desvío desactivado') : tr('Desvío activo hacia {0}', [app.features.forwardTarget]));
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
    return _Drawer(
      title: tr('Dispositivos de audio · {0}', [Platform.isMacOS ? 'CoreAudio' : Platform.isWindows ? 'WASAPI' : 'ALSA/PulseAudio']),
      onClose: widget.onClose,
      children: [
        Row(children: [
          Expanded(child: _Labeled(tr('Micrófono'), _picker(a.captureName, a.inputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: v, playback: a.playbackName)))),
          const SizedBox(width: 8),
          Expanded(
              child: _Labeled(tr('Altavoz / auricular'), _picker(a.playbackName, a.outputs.map((d) => d.name).toList(), (v) => a.setDevices(capture: a.captureName, playback: v)))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text(tr('Volumen'), style: TextStyle(fontSize: 10, color: NxColors.gray500)),
          Expanded(child: Slider(value: a.speakerVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(speaker: v))),
          Text(tr('Mic'), style: TextStyle(fontSize: 10, color: NxColors.gray500)),
          Expanded(child: Slider(value: a.micVolume.clamp(0, 2), min: 0, max: 2, onChanged: (v) => a.setVolumes(mic: v))),
          Pill(tr('AEC ON'), bg: NxColors.card, border: NxColors.border, mono: true, size: 9.5),
        ]),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Tactile(
            onTap: () {
              widget.onClose();
              context.findAncestorStateOfType<HomeScreenState>()?.go(NxTab.settings);
            },
            child: Text(tr('Tonos, avisos y más opciones en Ajustes →'),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: NxColors.goldDark)),
          ),
        ),
      ],
    );
  }
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
        decoration: BoxDecoration(color: NxColors.surface, border: Border(bottom: BorderSide(color: NxColors.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Tactile(onTap: onClose, child: Text(tr('Cerrar'), style: TextStyle(fontSize: 11.5, color: NxColors.gray400, fontWeight: FontWeight.w500))),
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
        Text(label, style: TextStyle(fontSize: 10, color: NxColors.gray500, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        child,
      ]);
}

// ---------------------------------------------------------------------------
// Navegación inferior
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onTap, required this.mwi, this.pending = 0});
  final NxTab tab;
  final ValueChanged<NxTab> onTap;
  final bool mwi;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final items = [
      (NxTab.terminal, NavGlyph.terminal, tr('Terminal')),
      (NxTab.voicemail, NavGlyph.voicemail, tr('Buzón')),
      (NxTab.contacts, NavGlyph.contacts, tr('Contactos')),
      (NxTab.history, NavGlyph.history, tr('Historial')),
      (NxTab.settings, NavGlyph.settings, tr('Ajustes')),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: NxColors.surface, border: Border(top: BorderSide(color: NxColors.border))),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tactile(
                onTap: () => onTap(it.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 5),
                  decoration: BoxDecoration(
                    gradient: tab == it.$1
                        ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [NxColors.goldSoft, NxColors.card])
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tab == it.$1 ? NxColors.goldBorder : Colors.transparent),
                    boxShadow: tab == it.$1
                        ? [BoxShadow(color: NxColors.gold.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3))]
                        : null,
                  ),
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedScale(
                        scale: tab == it.$1 ? 1.06 : 1.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: NavIcon(it.$2,
                            size: 21,
                            color: tab == it.$1 ? NxColors.goldDark : NxColors.gray500,
                            fill: tab == it.$1 ? NxColors.gold.withValues(alpha: 0.14) : null),
                      ),
                      const SizedBox(height: 3),
                      Text(it.$3,
                          style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.15,
                              fontWeight: tab == it.$1 ? FontWeight.w700 : FontWeight.w500,
                              color: tab == it.$1 ? NxColors.goldDark : NxColors.gray500)),
                    ]),
                    // Indicador superior de la pestaña activa
                    Positioned(
                      top: -7,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: tab == it.$1 ? 18 : 0,
                        height: 3,
                        decoration: BoxDecoration(color: NxColors.gold, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    if (it.$1 == NxTab.voicemail && mwi) Positioned(top: -1, right: 16, child: Led(NxColors.gold, size: 7)),
                    if (it.$1 == NxTab.history && pending > 0)
                      Positioned(
                        top: -3,
                        right: 12,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 15),
                          height: 15,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: NxColors.red, borderRadius: BorderRadius.circular(99)),
                          child: Text('$pending', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Aviso de versión nueva (leída de la carpeta compartida).
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();
  @override
  Widget build(BuildContext context) {
    final u = AppController.I.updates;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
      color: NxColors.goldSoft,
      child: Row(children: [
        Icon(Icons.system_update_alt_rounded, size: 16, color: NxColors.goldDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tr('Nueva versión {0} disponible', [u.availableVersion]) + (u.notes.isEmpty ? '' : ' · ${u.notes}'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NxColors.goldDark)),
        ),
        NxButton(label: tr('Instalar'), tone: NxTone.dark, height: 26, radius: 9, fontSize: 10.5, onTap: u.install),
        IconButton(icon: Icon(Icons.close, size: 15, color: NxColors.gray500), onPressed: u.dismiss, tooltip: tr('Más tarde')),
      ]),
    );
  }
}

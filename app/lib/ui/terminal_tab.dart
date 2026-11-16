import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/call_state_machine.dart';
import '../core/feature_managers.dart';
import '../core/models.dart';
import '../engine/sip_engine.dart';
import 'call_context.dart';
import 'home.dart';
import 'theme.dart';
import 'widgets.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});
  @override
  State<TerminalTab> createState() => TerminalTabState();
}

class TerminalTabState extends State<TerminalTab> {
  final app = AppController.I;
  final _dial = TextEditingController();
  final _dialFocus = FocusNode();
  bool _expanded = false;
  bool _dtmfMode = false;
  String _dtmfSent = '';
  int? _dtmfCallId;
  final _kbFocus = FocusNode(debugLabel: 'teclado-dtmf');

  /// Llamada activa en primer plano: el teclado envía tonos DTMF (como un teléfono físico).
  bool get _inCall {
    final f = app.calls.focused;
    return f != null && f.state == CallState.active;
  }
  bool _showStats = false;
  bool _transferOpen = false;
  Map<String, dynamic>? _stats;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final f = app.calls.focused;
      if (_showStats && f != null && f.state.isLive) _stats = app.calls.stats(f);
      if (app.calls.liveCalls.isNotEmpty) setState(() {});
    });
    app.calls.addListener(_onCalls);
  }

  void _onCalls() {
    final f = app.calls.focused;
    // Al entrar en conversación, el teclado físico pasa a enviar tonos
    if (f != null && f.state == CallState.active && !_kbFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _kbFocus.requestFocus() : null);
    }
    if (f == null || f.callId != _dtmfCallId) _dtmfSent = '';
    final live = f != null && (f.state == CallState.active || f.state == CallState.held);
    if (!live && (_dtmfMode || _showStats || (_transferOpen && f?.consultFor == null))) {
      setState(() {
        _dtmfMode = false;
        _showStats = false;
        _transferOpen = false;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    app.calls.removeListener(_onCalls);
    _dial.dispose();
    _dialFocus.dispose();
    _kbFocus.dispose();
    super.dispose();
  }

  void dialAndCall(String number) {
    _dial.text = number;
    _call();
  }

  void _press(String k) {
    if (_inCall || _dtmfMode) {
      final f = app.calls.focused;
      if (app.dtmf.send(k)) {
        setState(() {
          if (_dtmfCallId != f?.callId) {
            _dtmfSent = '';
            _dtmfCallId = f?.callId;
          }
          _dtmfSent = (_dtmfSent + k);
          if (_dtmfSent.length > 24) _dtmfSent = _dtmfSent.substring(_dtmfSent.length - 24);
        });
      }
      return;
    }
    final t = _dial.text;
    final sel = _dial.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _dial.value = TextEditingValue(text: t.replaceRange(start, end, k), selection: TextSelection.collapsed(offset: start + 1));
  }

  void _backspace() {
    final t = _dial.text;
    if (t.isEmpty) return;
    _dial.value = TextEditingValue(text: t.substring(0, t.length - 1), selection: TextSelection.collapsed(offset: t.length - 1));
  }

  void _call() {
    final number = _dial.text.trim();
    if (number.isEmpty) {
      final last = app.history.entries.where((e) => e.type == HistoryType.outgoing).firstOrNull;
      if (last != null) {
        setState(() => _dial.text = last.number);
      } else {
        app.showToast('Introduce un número o extensión para llamar');
      }
      return;
    }
    final c = app.calls.makeCall(app.lines.selectedLine, number);
    if (c != null) {
      _dial.clear();
    } else if (app.calls.lastError != null) {
      app.showToast(app.calls.lastError!);
      app.calls.lastError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = app.lines.lines;
    final visible = _expanded ? lines : lines.take(2).toList();
    final sel = app.lines.selectedLine;
    final anyTls = lines.any((l) => l.account.isComplete && l.account.transport == SipTransport.tls);
    final anySrtp = lines.any((l) => l.account.isComplete && l.account.srtp > 0);
    final reg = app.overallReg;

    return Focus(
      focusNode: _kbFocus,
      onKeyEvent: (node, event) {
        final ch = event.character;
        if (_inCall && event is KeyDownEvent && ch != null && ch.length == 1 && '0123456789*#'.contains(ch)) {
          _press(ch);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 14),
      children: [
        // 1. Líneas
        Row(children: [
          const Expanded(child: SectionLabel('Líneas SIP simultáneas')),
          Led(regColor(reg), size: 6),
          const SizedBox(width: 4),
          Text(
            reg == RegState.registered
                ? (anyTls ? (anySrtp ? 'TLS/SRTP' : 'TLS') : 'UDP')
                : reg == RegState.registering
                    ? 'Registrando'
                    : 'Sin red SIP',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: reg == RegState.registered ? NxColors.greenText : NxColors.redText),
          ),
          const SizedBox(width: 8),
          Tactile(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '− Ver 2 líneas' : '+ Ver ${lines.length > 2 ? lines.length : 4} líneas',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: NxColors.goldDark)),
          ),
        ]),
        const SizedBox(height: 8),
        _LinesGrid(lines: visible, showAdd: _expanded && lines.length < 8, onFocusCall: (c) => setState(() => app.calls.focus(c))),
        const SizedBox(height: 12),

        // 1B. Teclas BLF y órbitas
        _BlfPanel(onMessage: app.showToast),
        const SizedBox(height: 12),

        // 2. Pantalla LCD
        _Lcd(
          dtmfMode: _dtmfMode || _inCall,
          dtmfSent: _dtmfSent,
          showStats: _showStats,
          stats: _stats,
          transferOpen: _transferOpen,
          dialText: () => _dial.text,
          onToggleDtmf: () => setState(() => _dtmfMode = !_dtmfMode),
          onToggleStats: () => setState(() {
            _showStats = !_showStats;
            final f = app.calls.focused;
            if (_showStats && f != null) _stats = app.calls.stats(f);
          }),
          onTransfer: (open) => setState(() => _transferOpen = open),
        ),
        const SizedBox(height: 12),

        // 3. Marcador y línea de salida
        _DialInput(controller: _dial, focus: _dialFocus, dtmf: _dtmfMode || _inCall, onBackspace: _backspace, onSubmit: _call),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Salida por:', style: TextStyle(fontSize: 11, color: NxColors.gray500)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [
                for (final l in lines.where((l) => l.account.isComplete || l.index < 2)) ...[
                  _OutPill(line: l, selected: l.index == sel.index, onTap: () => app.lines.select(l.index)),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // 4. Teclado
        _Keypad(onKey: _press, onVoicemail: () => app.dialVoicemail(sel)),
        const SizedBox(height: 10),

        // 5. Barra de llamada
        Row(children: [
          Expanded(
            flex: 3,
            child: NxButton(label: 'Limpiar', height: 44, radius: 16, onTap: () => setState(() => _dial.clear())),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 9,
            child: NxButton(
              label: 'Llamar desde ${sel.label} (${sel.extension})',
              icon: Icons.call,
              tone: NxTone.dark,
              height: 44,
              radius: 16,
              fontSize: 13.5,
              onTap: _call,
            ),
          ),
        ]),
      ],
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjetas de línea
// ---------------------------------------------------------------------------

class _LinesGrid extends StatelessWidget {
  const _LinesGrid({required this.lines, required this.showAdd, required this.onFocusCall});
  final List<SipLine> lines;
  final bool showAdd;
  final ValueChanged<CallSession> onFocusCall;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[for (final l in lines) _LineCard(line: l, onFocusCall: onFocusCall), if (showAdd) const _AddLineCard()];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
    });
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.onFocusCall});
  final SipLine line;
  final ValueChanged<CallSession> onFocusCall;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final status = app.calls.lineStatus(line);
    final call = app.calls.primaryCall(line);
    final focused = call != null ? app.calls.focusedId == call.callId : (app.lines.selected == line.index && app.calls.focused == null);
    final vm = app.voicemail.newFor(line);
    final count = app.calls.callsOnAcc(line.accId).length;

    Color led = NxColors.green;
    bool pulse = false;
    Color border = focused ? NxColors.gold : NxColors.border;
    Color bg = focused ? Colors.white : NxColors.surface;
    Widget badge;
    switch (status) {
      case LineStatus.disconnected:
        led = NxColors.red500;
        badge = const Text('Desconectada', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NxColors.red));
      case LineStatus.ringing:
        led = NxColors.gold;
        pulse = true;
        border = NxColors.gold;
        bg = NxColors.goldSoft;
        badge = const Text('Sonando…', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: NxColors.goldDark));
      case LineStatus.held:
        led = NxColors.amber;
        border = NxColors.amberBorder.withValues(alpha: 0.8);
        bg = NxColors.amberSoft;
        badge = const Text('Retenida', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NxColors.amberText));
      case LineStatus.busy:
        final outgoing = call != null && (call.state == CallState.outgoing || call.state == CallState.ringing || call.state == CallState.connecting);
        led = outgoing ? NxColors.sky : NxColors.green;
        border = outgoing ? NxColors.border : NxColors.green.withValues(alpha: 0.7);
        bg = outgoing ? bg : const Color(0x4DECFDF5);
        badge = outgoing
            ? const Text('Llamando…', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: NxColors.skyText))
            : Text(fmtDuration(call?.duration ?? Duration.zero),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: NxColors.greenText, fontFamily: kMono));
      case LineStatus.free:
        badge = const Text('Libre', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: NxColors.gray400));
    }

    return Tactile(
      onTap: () {
        app.lines.select(line.index);
        if (call != null) onFocusCall(call);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 76,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: focused || status == LineStatus.ringing ? [BoxShadow(color: NxColors.gold.withValues(alpha: 0.18), spreadRadius: 3)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Led(led, size: 8, pulse: pulse),
            const SizedBox(width: 7),
            Text(line.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
            const SizedBox(width: 6),
            Pill(line.extension, mono: true, size: 10.5, fg: NxColors.gray700),
            if (count > 1) ...[const SizedBox(width: 4), Pill('×$count', size: 9.5, fg: NxColors.goldDark, bg: NxColors.goldSoft)],
            const Spacer(),
            badge,
          ]),
          const Spacer(),
          if (call != null) ...[
            Text(call.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(call.displayName != call.remoteNumber ? call.remoteNumber : call.state.label,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: NxColors.gray500, fontFamily: kMono)),
          ] else ...[
            Text(line.account.name.isEmpty ? 'Sin configurar' : line.account.name,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: NxColors.gray500)),
            Row(children: [
              Expanded(
                child: Text(line.account.server.isEmpty ? '—' : line.account.server,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: NxColors.gray400, fontFamily: kMono)),
              ),
              if (vm > 0)
                Tactile(
                  onTap: () => context.findAncestorStateOfType<HomeScreenState>()?.go(NxTab.voicemail),
                  child: Pill('Buzón ($vm)', mono: true, size: 9, fg: NxColors.goldDark, bg: NxColors.goldSoft),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _AddLineCard extends StatelessWidget {
  const _AddLineCard();
  @override
  Widget build(BuildContext context) => Tactile(
        onTap: () => AppController.I.addLine(),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: NxColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NxColors.goldBorder),
          ),
          child: const Center(child: Text('+ Añadir línea', style: TextStyle(color: NxColors.goldDark, fontWeight: FontWeight.w700, fontSize: 11.5))),
        ),
      );
}

// ---------------------------------------------------------------------------
// Teclas BLF y órbitas de aparcamiento
// ---------------------------------------------------------------------------

class _BlfPanel extends StatelessWidget {
  const _BlfPanel({required this.onMessage});
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final keys = app.blf.keys;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: NxColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NxColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(children: [
            const Expanded(child: SectionLabel('Teclas rápidas BLF & órbitas park', size: 10)),
            Tactile(
              onTap: () => app.dialVoicemail(app.lines.selectedLine),
              child: const Text('Buzón (*97)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: NxColors.goldDark)),
            ),
          ]),
        ),
        if (keys.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Configura las teclas en la pestaña SIP', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
          )
        else
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 12) / 3;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in keys) SizedBox(width: w, child: _BlfKeyTile(k: k, onTap: () => onMessage(app.blf.press(k, app.lines.selectedLine)))),
            ]);
          }),
      ]),
    );
  }
}

class _BlfKeyTile extends StatelessWidget {
  const _BlfKeyTile({required this.k, required this.onTap});
  final BlfKey k;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color dot = NxColors.green;
    bool pulse = false;
    String tag = 'Libre';
    Color border = NxColors.border;
    Color bg = Colors.white;
    if (k.park) {
      if (k.state == BlfState.parked) {
        dot = NxColors.amber;
        pulse = true;
        tag = 'Aparcada • Rec.';
        border = NxColors.amberBorder;
        bg = NxColors.amberSoft;
      } else {
        dot = const Color(0xFFD1D5DB);
        tag = 'Órbita libre';
      }
    } else {
      switch (k.state) {
        case BlfState.busy:
          dot = NxColors.red500;
          tag = 'Ocupada';
        case BlfState.ringing:
          dot = NxColors.gold;
          pulse = true;
          tag = 'Capturar **';
          border = NxColors.gold;
          bg = NxColors.goldSoft.withValues(alpha: 0.6);
        case BlfState.unknown:
          dot = const Color(0xFFD1D5DB);
          tag = 'Sin estado';
        default:
          break;
      }
    }
    return Tactile(
      onTap: onTap,
      tooltip: k.remote.isNotEmpty ? 'Con ${k.remote}' : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Led(dot, size: 6, pulse: pulse),
            const SizedBox(width: 5),
            Expanded(child: Text(k.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
          Text('${k.park ? 'Slot' : 'Ext.'} ${k.ext} • $tag',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: NxColors.gray500, fontFamily: kMono)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla LCD con controles adaptativos
// ---------------------------------------------------------------------------

class _Lcd extends StatelessWidget {
  const _Lcd({
    required this.dtmfMode,
    required this.dtmfSent,
    required this.showStats,
    required this.stats,
    required this.transferOpen,
    required this.dialText,
    required this.onToggleDtmf,
    required this.onToggleStats,
    required this.onTransfer,
  });
  final bool dtmfMode, showStats, transferOpen;
  final String dtmfSent;
  final Map<String, dynamic>? stats;
  final String Function() dialText;
  final VoidCallback onToggleDtmf, onToggleStats;
  final ValueChanged<bool> onTransfer;

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    final call = app.calls.focused;
    if (call == null || !call.state.isLive && app.calls.liveCalls.isEmpty && call.endedAt != null && DateTime.now().difference(call.endedAt!).inSeconds > 3) {
      return _idle(app);
    }
    return NxPanel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (call.state == CallState.incoming) _ringing(app, call) else _session(app, call),
        if (showStats && call.state.isLive) _StatsBox(stats: stats),
        ..._controls(context, app, call),
        if (call.state.isLive && call.state != CallState.incoming)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 9),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: NxColors.border))),
            child: CallContextBlock(
              key: ValueKey('ctx-${call.callId}'),
              note: call.note,
              tags: call.tags,
              onNote: (v) => call.note = v,
              onToggleTag: (id) => app.calls.toggleTag(call, id),
            ),
          ),
        if (transferOpen || call.consultFor != null) _TransferPanel(call: call, initial: dialText(), onClose: () => onTransfer(false)),
      ]),
    );
  }

  Widget _idle(AppController app) {
    final line = app.lines.selectedLine;
    final a = line.account;
    final registered = line.reg == RegState.registered;
    final others = app.calls.liveCalls;
    return NxPanel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${line.label} • Extensión ${line.extension}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Pill(registered ? 'Registrada' : line.reg.label,
                    round: true, fg: registered ? NxColors.greenText : NxColors.redText, bg: registered ? NxColors.greenSoft : NxColors.redSoft),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  if (a.name.isNotEmpty) a.name,
                  'Códec ${app.audio.preferredCodecLabel.replaceAll(' HD', '')} (${a.transportLabel})',
                ].join(' • '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: NxColors.gray500),
              ),
              if (!registered && line.regReason.isNotEmpty)
                Text('${line.regCode > 0 ? '${line.regCode} ' : ''}${line.regReason}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: NxColors.red)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(registered ? 'LISTO' : 'SIN REGISTRO',
                style: const TextStyle(fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w600, color: NxColors.gray700)),
            Text(a.srtp > 0 ? 'SRTP ON' : (a.transport == SipTransport.tls ? 'TLS ON' : 'RTP'),
                style: const TextStyle(fontFamily: kMono, fontSize: 10, color: NxColors.goldDark)),
          ]),
        ]),
        for (final o in others)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Tactile(
              onTap: () => app.calls.focus(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: NxColors.amberSoft.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Text('Sesión en curso en ${app.calls.lineOf(o)?.label ?? 'IP'} (${o.displayName})',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: NxColors.amberText)),
                  ),
                  const Text('Ver sesión →',
                      style: TextStyle(fontSize: 11, color: NxColors.amberText, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _ringing(AppController app, CallSession c) {
    final line = app.calls.lineOf(c);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pill('LLAMADA ENTRANTE EN ${line?.label ?? 'IP'}${line != null ? ' (EXT. ${line.extension})' : ''}',
              round: true, size: 9.5, fg: NxColors.goldDark, bg: NxColors.goldSoft),
          const SizedBox(height: 4),
          Text(c.displayName.isEmpty ? 'Número oculto' : c.displayName,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (c.displayName != c.remoteNumber) Text(c.remoteNumber, style: const TextStyle(fontFamily: kMono, fontSize: 12, color: NxColors.gray600)),
          CallerContext(number: c.remoteNumber),
        ]),
      ),
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: NxColors.goldSoft, shape: BoxShape.circle, border: Border.all(color: NxColors.goldBorder)),
        child: const Icon(Icons.ring_volume_outlined, color: NxColors.goldDark, size: 20),
      ),
    ]);
  }

  Widget _session(AppController app, CallSession c) {
    final line = app.calls.lineOf(c);
    final s = c.state;
    final rec = app.calls.recordingCallId == c.callId;
    final (badgeText, badgeFg, badgeBg) = switch (s) {
      CallState.outgoing || CallState.ringing || CallState.connecting => ('Conectando SIP…', const Color(0xFF075985), NxColors.skySoft),
      CallState.held => ('En espera (Hold)', NxColors.amberText, const Color(0xFFFEF3C7)),
      CallState.transferring => ('Transfiriendo…', NxColors.goldDark, NxColors.goldSoft),
      CallState.ended => ('Finalizada', NxColors.gray600, NxColors.surfaceHover),
      CallState.failed => ('Fallida ${c.statusCode}', NxColors.redText, NxColors.redSoft),
      _ => (app.calls.conference && !c.remoteHold ? 'Conferencia a 3' : (c.remoteHold ? 'Te han retenido' : 'RTP activo'), const Color(0xFF065F46), const Color(0xFFD1FAE5)),
    };
    final secure = line?.account.srtp != null && line!.account.srtp > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${line?.label ?? 'IP DIRECTA'}${line != null ? ' • Ext. ${line.extension}' : ''}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NxColors.gray500)),
              const SizedBox(width: 6),
              Pill(badgeText, round: true, fg: badgeFg, bg: badgeBg),
            ]),
            const SizedBox(height: 2),
            Text(c.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (c.displayName != c.remoteNumber) Text(c.remoteNumber, style: const TextStyle(fontFamily: kMono, fontSize: 12, color: NxColors.gray500)),
            CallerContext(number: c.remoteNumber, showLastNote: false),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtDuration(c.duration), style: const TextStyle(fontFamily: kMono, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (s == CallState.active || s == CallState.held)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tactile(
                  tooltip: rec ? 'Detener grabación' : 'Grabar llamada (WAV local)',
                  onTap: () => app.calls.toggleRecording(c, (x) => recordingPathFor(x, app.calls.lineOf(x))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: rec ? NxColors.redSoft : Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: rec ? NxColors.redBorder : NxColors.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Led(rec ? NxColors.red500 : NxColors.gray400, size: 6, pulse: rec),
                      const SizedBox(width: 3),
                      Text('REC',
                          style: TextStyle(fontFamily: kMono, fontSize: 9.5, fontWeight: FontWeight.w700, color: rec ? NxColors.redText : NxColors.gray600)),
                    ]),
                  ),
                ),
              ),
            Tactile(
              tooltip: 'Ver telemetría RTP / MOS',
              onTap: s.isLive ? onToggleStats : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: showStats ? NxColors.gold : NxColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${_codecLabel(stats, app)} • ${(stats?['srtp'] == true || secure) ? 'SRTP' : 'RTP'}',
                      style: const TextStyle(fontFamily: kMono, fontSize: 10, color: NxColors.gray600)),
                  const SizedBox(width: 4),
                  const Text('ⓘ', style: TextStyle(fontSize: 10, color: NxColors.goldDark, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ]),
      ]),
      if (dtmfMode)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: NxColors.dark, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.dialpad, size: 13, color: NxColors.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Text(dtmfSent.isEmpty ? 'Teclado en modo tonos DTMF: pulsa las teclas' : 'Tonos enviados',
                  style: const TextStyle(color: NxColors.gold, fontSize: 11, fontWeight: FontWeight.w500)),
            ),
            if (dtmfSent.isNotEmpty)
              Text(dtmfSent, style: const TextStyle(color: Colors.white, fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ]),
        ),
    ]);
  }

  static String _codecLabel(Map<String, dynamic>? stats, AppController app) {
    final c = stats?['codec']?.toString() ?? '';
    if (c.isEmpty) return app.audio.preferredCodecLabel.replaceAll(' HD', '');
    return switch (c.toUpperCase()) { 'G722' => 'G.722', 'PCMA' => 'G.711a', 'PCMU' => 'G.711u', 'OPUS' => 'Opus', _ => c };
  }

  List<Widget> _controls(BuildContext context, AppController app, CallSession c) {
    final m = app.calls;
    final s = c.state;
    final line = m.lineOf(c);
    bool can(CallAction a) => m.can(c, a);
    final hasOther = m.liveCalls.any((x) => x.callId != c.callId && (x.state == CallState.active || x.state == CallState.held));

    Widget grid(List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: NxColors.border))),
          child: LayoutBuilder(builder: (context, cons) {
            final w = (cons.maxWidth - 16) / 3;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ch in children) SizedBox(width: ch is _Span ? w * ch.span + 8 * (ch.span - 1) : w, child: ch is _Span ? ch.child : ch),
            ]);
          }),
        );

    if (s == CallState.incoming) {
      return [
        grid([
          _Span(2, NxButton(label: 'Contestar llamada', tone: NxTone.emerald, height: 38, onTap: () => m.answer(c))),
          NxButton(label: 'Rechazar', tone: NxTone.red, height: 38, onTap: () => m.reject(c)),
        ])
      ];
    }
    if (s == CallState.outgoing || s == CallState.ringing || s == CallState.connecting || s == CallState.transferring) {
      return [
        grid([
          _Span(3, NxButton(label: s == CallState.transferring ? 'Colgar' : 'Cancelar llamada', tone: NxTone.red, height: 38, onTap: () => m.hangup(c))),
        ])
      ];
    }
    if (!s.isLive) return const [];

    final held = s == CallState.held;
    return [
      grid([
        held
            ? NxButton(label: 'Recuperar', tone: NxTone.amber, height: 38, onTap: () => m.unhold(c))
            : NxButton(label: 'Retener', height: 38, onTap: can(CallAction.hold) ? () => m.hold(c) : null),
        NxButton(label: 'Transferir', height: 38, onTap: can(CallAction.transfer) && c.consultFor == null ? () => onTransfer(!transferOpen) : null),
        NxButton(
          label: m.muted ? 'Silenciado' : 'Silenciar',
          height: 38,
          tone: m.muted ? NxTone.gold : NxTone.surface,
          onTap: () => m.setMute(!m.muted),
        ),
        hasOther
            ? NxButton(label: 'Alternar', height: 38, tone: NxTone.gold, bold: true, onTap: m.swap)
            : NxButton(label: 'DTMF', height: 38, tone: dtmfMode ? NxTone.dark : NxTone.surface, onTap: can(CallAction.dtmf) ? onToggleDtmf : null),
        hasOther
            ? NxButton(
                label: m.conference ? 'Dividir conf.' : 'Conferencia',
                height: 38,
                tone: m.conference ? NxTone.dark : NxTone.surface,
                onTap: () {
                  m.toggleConference();
                  app.showToast(m.conference ? 'Conferencia dividida · la otra llamada vuelve a espera' : 'Conferencia a 3 vías activa (mezcla local PJSIP)');
                },
              )
            : NxButton(
                label: 'Aparcar 71',
                height: 38,
                onTap: can(CallAction.transfer)
                    ? () {
                        if (m.park(c)) app.showToast('Aparcando ${c.displayName} en la órbita de FreePBX (70 → 71…)');
                      }
                    : null,
              ),
        NxButton(label: 'Colgar L${line?.number ?? ''}', tone: NxTone.red, height: 38, onTap: () => m.hangup(c)),
      ])
    ];
  }
}

class _Span extends StatelessWidget {
  const _Span(this.span, this.child);
  final int span;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _StatsBox extends StatelessWidget {
  const _StatsBox({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    double v(String k) => ((stats?[k] as num?) ?? 0) / 10.0;
    final mos = v('mos_x10');
    final loss = v('loss_x10');
    final mosColor = mos >= 4.0 ? NxColors.greenText : (mos >= 3.4 ? NxColors.amberText : NxColors.redText);
    final mosBg = mos >= 4.0 ? NxColors.greenSoft : (mos >= 3.4 ? NxColors.amberSoft : NxColors.redSoft);
    Widget box(String label, String value, [Color color = NxColors.text]) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text(label, style: const TextStyle(fontSize: 9, color: NxColors.gray400)),
              Text(value, style: TextStyle(fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: NxColors.goldBorder)),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('Telemetría media RTP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          Pill(stats == null ? 'MOS —' : 'MOS ${mos.toStringAsFixed(1)} / 5.0', mono: true, fg: mosColor, bg: mosBg),
        ]),
        const Divider(height: 12, color: NxColors.surfaceHover),
        Row(children: [
          box('JITTER', '${v('jitter_x10').toStringAsFixed(1)} ms'),
          const SizedBox(width: 8),
          box('PACKET LOSS', '${loss.toStringAsFixed(1)}%', loss < 1 ? NxColors.greenText : NxColors.redText),
          const SizedBox(width: 8),
          box('LATENCIA RTT', '${(stats?['rtt_ms'] as num?)?.toInt() ?? 0} ms'),
        ]),
      ]),
    );
  }
}

class _TransferPanel extends StatefulWidget {
  const _TransferPanel({required this.call, required this.initial, required this.onClose});
  final CallSession call;
  final String initial;
  final VoidCallback onClose;
  @override
  State<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<_TransferPanel> {
  late final _ctl = TextEditingController(text: widget.initial);
  final app = AppController.I;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final consulting = c.consultFor != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: NxColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Transferencia SIP (REFER)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          if (!consulting) Tactile(onTap: widget.onClose, child: const Text('Cancelar', style: TextStyle(fontSize: 11, color: NxColors.gray400))),
        ]),
        const SizedBox(height: 8),
        if (!consulting) ...[
          TextField(
            controller: _ctl,
            autofocus: true,
            style: const TextStyle(fontFamily: kMono, fontSize: 12),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9*#+]'))],
            decoration: const InputDecoration(hintText: 'Extensión o número destino (ej. 205)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: NxButton(
                label: 'Transferencia ciega',
                tone: NxTone.white,
                height: 34,
                radius: 12,
                onTap: () {
                  if (app.transfers.blind(c, _ctl.text)) {
                    app.showToast('REFER enviado: transferencia ciega a ${_ctl.text}');
                    widget.onClose();
                  } else {
                    app.showToast('Indica el destino de la transferencia');
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NxButton(
                label: 'Atendida (consultar)',
                tone: NxTone.dark,
                height: 34,
                radius: 12,
                onTap: () {
                  final cs = app.transfers.startAttended(c, _ctl.text);
                  if (cs == null) {
                    app.showToast('Indica el destino para consultar');
                  } else {
                    app.showToast('Llamada original en espera · consultando con ${_ctl.text}…');
                    widget.onClose();
                  }
                },
              ),
            ),
          ]),
        ] else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: NxColors.goldSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: NxColors.goldBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Interlocutor original (${app.calls.byId(c.consultFor!)?.displayName ?? ''}) en espera. Hablando con '),
                  TextSpan(text: c.remoteNumber, style: const TextStyle(fontFamily: kMono, fontWeight: FontWeight.w700)),
                  const TextSpan(text: '.'),
                ]),
                style: const TextStyle(fontSize: 11, color: NxColors.goldDark, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: NxButton(
                    label: 'Completar transferencia',
                    tone: NxTone.emerald,
                    height: 30,
                    radius: 8,
                    fontSize: 11,
                    onTap: () {
                      if (app.transfers.complete(c)) {
                        app.showToast('REFER con Replaces enviado hacia ${c.remoteNumber}');
                      } else {
                        app.showToast('No se pudo completar la transferencia');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NxButton(
                    label: 'Cancelar y recuperar',
                    tone: NxTone.white,
                    height: 30,
                    radius: 8,
                    fontSize: 11,
                    onTap: () {
                      app.transfers.cancel(c);
                      app.showToast('Consulta cancelada · llamada original recuperada');
                    },
                  ),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Marcador, salida y teclado
// ---------------------------------------------------------------------------

class _DialInput extends StatelessWidget {
  const _DialInput({required this.controller, required this.focus, required this.dtmf, required this.onBackspace, required this.onSubmit});
  final TextEditingController controller;
  final FocusNode focus;
  final bool dtmf;
  final VoidCallback onBackspace, onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focus,
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        decoration: BoxDecoration(
          color: NxColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focus.hasFocus ? NxColors.gold : NxColors.border),
          boxShadow: focus.hasFocus ? [BoxShadow(color: NxColors.gold.withValues(alpha: 0.18), spreadRadius: 3)] : null,
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: !dtmf,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(fontFamily: kMono, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9*#+]'))],
              decoration: InputDecoration(
                hintText: dtmf ? 'Modo DTMF: pulsa el teclado' : 'Introduce número o extensión...',
                hintStyle: const TextStyle(fontFamily: kMono, fontSize: 16, fontWeight: FontWeight.w600, color: NxColors.gray400, letterSpacing: -0.3),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                isDense: true,
              ),
            ),
          ),
          Tactile(
            onTap: onBackspace,
            tooltip: 'Borrar dígito',
            child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.backspace_outlined, size: 20, color: NxColors.gray400)),
          ),
        ]),
      ),
    );
  }
}

class _OutPill extends StatelessWidget {
  const _OutPill({required this.line, required this.selected, required this.onTap});
  final SipLine line;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tactile(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? NxColors.goldSoft : NxColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? NxColors.gold : NxColors.border),
          ),
          child: Text('Línea ${line.number} • Ext. ${line.extension}',
              style: TextStyle(
                  fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? NxColors.goldDark : NxColors.gray500)),
        ),
      );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onVoicemail});
  final ValueChanged<String> onKey;
  final VoidCallback onVoicemail;

  static const keys = [
    ('1', 'VOICEMAIL'), ('2', 'ABC'), ('3', 'DEF'),
    ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'),
    ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
    ('*', ''), ('0', '+'), ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 16) / 3;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in keys)
          SizedBox(
            width: w,
            height: 44,
            child: Tactile(
              onTap: () => onKey(k.$1),
              onLongPress: k.$1 == '0' ? () => onKey('+') : (k.$1 == '1' ? onVoicemail : null),
              tooltip: k.$1 == '1' ? 'Mantén pulsado para el buzón (*97)' : null,
              child: Builder(builder: (context) {
                return Container(
                  decoration: BoxDecoration(
                    color: NxColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NxColors.border.withValues(alpha: 0.8)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(k.$1, style: const TextStyle(fontFamily: kMono, fontSize: 16, fontWeight: FontWeight.w700, height: 1)),
                    if (k.$2.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(k.$2, style: TextStyle(fontSize: k.$2 == '+' ? 9 : 8, color: NxColors.gray400, letterSpacing: 1.6, height: 1)),
                    ],
                  ]),
                );
              }),
            ),
          ),
      ]);
    });
  }
}

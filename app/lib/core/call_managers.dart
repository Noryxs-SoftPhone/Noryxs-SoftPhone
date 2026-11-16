// Gestor de sesiones de llamada, transferencias y DTMF.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';
import 'call_state_machine.dart';
import 'models.dart';
import 'sip_managers.dart';

class CallSessionManager extends ChangeNotifier {
  CallSessionManager(this._engine, this._lines);
  final SipEngine _engine;
  final MultiLineManager _lines;

  /// Llamadas indexadas por id del motor. Las finalizadas se muestran
  /// unos segundos y después se retiran.
  final Map<int, CallSession> _calls = {};
  int? focusedId;
  bool muted = false;
  String? lastError;

  void Function(CallSession call)? onCallEnded;
  void Function(CallSession call)? onIncoming;
  String Function(String number)? contactLookup;

  List<CallSession> get calls => _calls.values.where((c) => !c.service).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Conferencia local a 3 activa.
  bool conference = false;

  /// Llamada que se está grabando (o null).
  int? recordingCallId;
  String? lastRecordingPath;
  List<CallSession> get liveCalls => calls.where((c) => c.state.isLive).toList();
  CallSession? byId(int id) => _calls[id];
  CallSession? get focused => focusedId == null ? null : _calls[focusedId];
  bool get hasActiveCall => _calls.values.any((c) => c.state == CallState.active);
  List<CallSession> callsOnAcc(int accId) => liveCalls.where((c) => c.accId == accId).toList();

  bool can(CallSession c, CallAction a) => CallStateMachine.can(c.state, a);

  /// Notifica cambios hechos desde la interfaz (nota, etiquetas).
  void touch() => notifyListeners();

  void toggleTag(CallSession c, String tagId) {
    c.tags.contains(tagId) ? c.tags.remove(tagId) : c.tags.add(tagId);
    notifyListeners();
  }

  // ---------------- Comandos ----------------

  CallSession? makeCall(SipLine line, String number) {
    lastError = null;
    final dest = number.trim();
    if (dest.isEmpty) return null;
    if (line.accId < 0 || line.reg != RegState.registered) {
      lastError = '${line.label} no está registrada';
      notifyListeners();
      return null;
    }
    final id = _engine.makeCall(line.accId, dest, holdOthers: true);
    if (id < 0) {
      lastError = 'No se pudo iniciar la llamada ($id)';
      notifyListeners();
      return null;
    }
    final c = CallSession(callId: id, accId: line.accId, incoming: false, remoteNumber: dest)
      ..contactName = contactLookup?.call(dest) ?? '';
    _calls[id] = c;
    focusedId = id;
    notifyListeners();
    return c;
  }

  /// Marca en silencio un código de servicio de FreePBX (*72NUM, *78…) por la línea
  /// indicada. No aparece en pantalla ni en el historial; se cuelga sola.
  bool serviceCall(SipLine line, String code, {Duration hangupAfter = const Duration(seconds: 7)}) {
    if (line.accId < 0 || line.reg != RegState.registered) return false;
    final id = _engine.makeCall(line.accId, code, holdOthers: false);
    if (id < 0) return false;
    final c = CallSession(callId: id, accId: line.accId, incoming: false, remoteNumber: code)..service = true;
    _calls[id] = c;
    Timer(hangupAfter, () {
      if (identical(_calls[id], c) && c.state.isLive) _engine.hangup(id);
    });
    return true;
  }

  /// Aparcar: transferencia ciega a la extensión de aparcamiento de FreePBX (70).
  bool park(CallSession c, {String parkExt = '70'}) {
    if (!can(c, CallAction.transfer)) return false;
    return _engine.transferBlind(c.callId, parkExt) == 0;
  }

  void toggleConference() {
    if (conference) {
      final keep = focused ?? liveCalls.where((c) => c.state == CallState.active).firstOrNull;
      if (keep != null) _engine.confSplit(keep.callId);
    } else {
      if (_engine.confJoin() != 0) lastError = 'Hacen falta dos llamadas establecidas para la conferencia';
    }
    notifyListeners();
  }

  void toggleRecording(CallSession c, String Function(CallSession) pathFor) {
    if (recordingCallId != null) {
      _engine.recStop();
      return;
    }
    final path = pathFor(c);
    if (_engine.recStart(c.callId, path) != 0) {
      lastError = 'No se pudo iniciar la grabación';
      notifyListeners();
    }
  }

  Map<String, dynamic>? stats(CallSession c) => _engine.callStats(c.callId);

  void answer(CallSession c) {
    if (!can(c, CallAction.answer)) return;
    _engine.answer(c.callId, holdOthers: true);
    c.ringSilenced = true;
    focusedId = c.callId;
    notifyListeners();
  }

  void reject(CallSession c) {
    if (!can(c, CallAction.reject)) return;
    c.ringSilenced = true;
    _engine.reject(c.callId);
    notifyListeners();
  }

  void silenceRing(CallSession c) {
    c.ringSilenced = true;
    notifyListeners();
  }

  void hangup(CallSession c) {
    if (!can(c, CallAction.hangup)) return;
    _engine.hangup(c.callId);
  }

  void hold(CallSession c) {
    if (!can(c, CallAction.hold)) return;
    _engine.hold(c.callId);
  }

  /// Recupera [c] y retiene automáticamente la que estuviera activa.
  void unhold(CallSession c) {
    if (!can(c, CallAction.unhold)) return;
    _engine.unhold(c.callId, holdOthers: true);
    focusedId = c.callId;
    notifyListeners();
  }

  /// Alternar: retiene la activa y recupera la otra.
  void swap() {
    final held = liveCalls.where((c) => c.state == CallState.held).toList();
    if (held.isEmpty) return;
    final target = held.firstWhere((c) => c.callId != focusedId, orElse: () => held.first);
    unhold(target);
  }

  void focus(CallSession c) {
    focusedId = c.callId;
    notifyListeners();
  }

  void setMute(bool m) {
    muted = m;
    _engine.setMute(m);
    notifyListeners();
  }

  // ---------------- Eventos del motor ----------------

  void onEvent(EngineEvent e) {
    switch (e.type) {
      case 'incoming':
        _onIncoming(e);
      case 'call':
        _onCallState(e);
      case 'xfer':
        _onXfer(e);
      case 'dnd_rejected':
        // Rechazada por No molestar: queda en el historial como perdida
        final c = CallSession(callId: e.callId, accId: e.accId, incoming: true, remoteNumber: e.str('remote_number'))
          ..remoteName = e.str('remote_name')
          ..contactName = contactLookup?.call(e.str('remote_number')) ?? ''
          ..state = CallState.incoming
          ..ringSilenced = true;
        _calls[e.callId] = c;
        notifyListeners();
      case 'conf':
        conference = e.intv('members') >= 2;
        notifyListeners();
      case 'rec':
        if (e.flag('recording')) {
          recordingCallId = e.callId;
          lastRecordingPath = e.str('path');
        } else {
          recordingCallId = null;
        }
        notifyListeners();
      case 'replaced':
        _calls.remove(e.intv('old_call_id'));
        notifyListeners();
    }
  }

  void _onIncoming(EngineEvent e) {
    final number = e.str('remote_number');
    final c = CallSession(callId: e.callId, accId: e.accId, incoming: true, remoteNumber: number)
      ..remoteName = e.str('remote_name')
      ..contactName = contactLookup?.call(number) ?? ''
      ..state = CallState.incoming;
    _calls[e.callId] = c; // reemplaza una finalizada con el mismo id
    focusedId ??= e.callId;
    onIncoming?.call(c);
    notifyListeners();
  }

  void _onCallState(EngineEvent e) {
    var c = _calls[e.callId];
    if (c == null || !c.state.isLive && e.str('state') != 'disconnected') {
      // Llamada desconocida (p.ej. sustitución por Replaces): crearla.
      c = CallSession(
        callId: e.callId,
        accId: e.accId,
        incoming: e.str('direction') == 'in',
        remoteNumber: e.str('remote_number'),
      );
      _calls[e.callId] = c;
    }
    if (!c.state.isLive) return; // eventos tardíos de una llamada ya cerrada

    final rn = e.str('remote_number');
    if (rn.isNotEmpty) c.remoteNumber = rn;
    final rname = e.str('remote_name');
    if (rname.isNotEmpty) c.remoteName = rname;
    c.statusCode = e.intv('status_code');
    c.statusText = e.str('status_text');
    c.remoteHold = e.str('media') == 'remote_hold';

    final inv = e.str('state');
    if (inv == 'confirmed' && c.connectedAt == null) {
      c.connectedAt = DateTime.now().subtract(Duration(seconds: e.intv('connect_duration')));
    }
    final next = CallStateMachine.fromEngine(
      invState: inv,
      incoming: c.incoming,
      localHold: e.flag('local_hold'),
      xferPending: e.flag('xfer_pending'),
      wasAnswered: c.connectedAt != null,
      statusCode: c.statusCode,
    );
    if (!CallStateMachine.isValidTransition(c.state, next)) {
      debugPrint('NORYXS: transición inesperada ${c.state} -> $next (llamada ${c.callId})');
    }
    c.state = next;
    if (next == CallState.active && !c.service) focusedId = c.callId;

    if (!next.isLive) _finish(c);
    notifyListeners();
  }

  void _finish(CallSession c) {
    c.endedAt = DateTime.now();
    if (!c.service) onCallEnded?.call(c);
    if (liveCalls.where((x) => x.state == CallState.active || x.state == CallState.held).length < 2) conference = false;

    // Consulta de transferencia cancelada/caída: recuperar la original.
    final orig = c.consultFor == null ? null : _calls[c.consultFor!];
    if (orig != null && orig.state == CallState.held) {
      _engine.unhold(orig.callId, holdOthers: false);
    }

    if (focusedId == c.callId) {
      final live = liveCalls;
      focusedId = live.isEmpty ? null : live.last.callId;
    }
    final ended = c;
    Timer(const Duration(seconds: 3), () {
      if (identical(_calls[ended.callId], ended)) {
        _calls.remove(ended.callId);
        notifyListeners();
      }
    });
  }

  void _onXfer(EngineEvent e) {
    final c = _calls[e.callId];
    if (c == null) return;
    c.statusText = 'Transferencia: ${e.intv('code')} ${e.str('text')}';
    if (e.flag('final') && e.intv('code') ~/ 100 != 2) {
      lastError = 'La transferencia falló (${e.intv('code')})';
    }
    notifyListeners();
  }

  // ---------------- Estado de líneas ----------------

  LineStatus lineStatus(SipLine line) {
    if (line.reg != RegState.registered) {
      // Una línea con llamadas en curso sigue mostrando su estado real.
      if (callsOnAcc(line.accId).isEmpty) return LineStatus.disconnected;
    }
    final cs = callsOnAcc(line.accId);
    if (cs.isEmpty) return LineStatus.free;
    if (cs.any((c) => c.state == CallState.incoming)) return LineStatus.ringing;
    if (cs.every((c) => c.state == CallState.held)) return LineStatus.held;
    return LineStatus.busy;
  }

  /// Llamada a mostrar en la tarjeta de línea (activa > entrante > retenida).
  CallSession? primaryCall(SipLine line) {
    final cs = callsOnAcc(line.accId);
    if (cs.isEmpty) return null;
    for (final s in [CallState.active, CallState.incoming, CallState.transferring, CallState.held]) {
      for (final c in cs) {
        if (c.state == s) return c;
      }
    }
    return cs.first;
  }

  SipLine? lineOf(CallSession c) => _lines.byAcc(c.accId);
}

/// Transferencias ciega y atendida (REFER / REFER con Replaces).
class CallTransferManager {
  CallTransferManager(this._engine, this._calls, this._lines);
  final SipEngine _engine;
  final CallSessionManager _calls;
  final MultiLineManager _lines;

  bool blind(CallSession c, String dest) {
    if (!_calls.can(c, CallAction.transfer) || dest.trim().isEmpty) return false;
    return _engine.transferBlind(c.callId, dest.trim()) == 0;
  }

  /// Retiene la llamada original y llama al destinatario de consulta
  /// por la misma línea.
  CallSession? startAttended(CallSession c, String dest) {
    if (!_calls.can(c, CallAction.transfer) || dest.trim().isEmpty) return null;
    final line = _lines.byAcc(c.accId);
    if (line == null) return null;
    final consult = _calls.makeCall(line, dest); // retiene la original
    consult?.consultFor = c.callId;
    return consult;
  }

  /// Completa: REFER a la original con Replaces de la consulta.
  bool complete(CallSession consult) {
    final origId = consult.consultFor;
    if (origId == null) return false;
    final orig = _calls.byId(origId);
    if (orig == null || !orig.state.isLive) return false;
    final ok = _engine.transferAttended(origId, consult.callId) == 0;
    if (ok) consult.consultFor = null; // no recuperar la original al colgar la consulta
    return ok;
  }

  /// Cancela: cuelga la consulta; la original se recupera al finalizar.
  void cancel(CallSession consult) => _calls.hangup(consult);
}

/// Envío de tonos DTMF (RFC 4733) a la llamada activa.
class DtmfManager {
  DtmfManager(this._engine, this._calls);
  final SipEngine _engine;
  final CallSessionManager _calls;

  bool send(String digits) {
    final c = _calls.focused;
    if (c == null || !_calls.can(c, CallAction.dtmf)) return false;
    return _engine.dtmf(c.callId, digits) == 0;
  }
}

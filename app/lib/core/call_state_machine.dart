// Máquina de estados de llamada.
// El motor nativo es la fuente de verdad del estado SIP; esta clase traduce
// sus eventos a estados del terminal e impide operaciones incompatibles.
import 'models.dart';

enum CallAction { answer, reject, silenceRing, hangup, hold, unhold, transfer, dtmf, mute }

class CallStateMachine {
  const CallStateMachine._();

  /// Traduce el estado INVITE de PJSIP (+ banderas) al estado del terminal.
  static CallState fromEngine({
    required String invState,
    required bool incoming,
    required bool localHold,
    required bool xferPending,
    required bool wasAnswered,
    required int statusCode,
  }) {
    switch (invState) {
      case 'incoming':
        return CallState.incoming;
      case 'calling':
        return CallState.outgoing;
      case 'early':
        return incoming ? CallState.incoming : CallState.ringing;
      case 'connecting':
        return CallState.connecting;
      case 'confirmed':
        if (xferPending) return CallState.transferring;
        return localHold ? CallState.held : CallState.active;
      case 'disconnected':
        // Saliente que nunca se contestó y terminó con error → fallida.
        if (!incoming && !wasAnswered && statusCode >= 300 && statusCode != 487) return CallState.failed;
        return CallState.ended;
      default:
        return incoming ? CallState.incoming : CallState.outgoing;
    }
  }

  /// ¿Está permitida [action] en [state]?
  static bool can(CallState state, CallAction action) {
    switch (action) {
      case CallAction.answer:
      case CallAction.reject:
      case CallAction.silenceRing:
        return state == CallState.incoming;
      case CallAction.hangup:
        return state.isLive;
      case CallAction.hold:
        return state == CallState.active;
      case CallAction.unhold:
        return state == CallState.held;
      case CallAction.transfer:
        return state == CallState.active || state == CallState.held;
      case CallAction.dtmf:
      case CallAction.mute:
        return state == CallState.active;
    }
  }

  /// Transiciones válidas (para detectar eventos incoherentes en depuración).
  static const Map<CallState, Set<CallState>> transitions = {
    CallState.incoming: {CallState.connecting, CallState.active, CallState.ended, CallState.failed},
    CallState.outgoing: {CallState.ringing, CallState.connecting, CallState.active, CallState.ended, CallState.failed},
    CallState.ringing: {CallState.connecting, CallState.active, CallState.ended, CallState.failed},
    CallState.connecting: {CallState.active, CallState.held, CallState.ended, CallState.failed},
    CallState.active: {CallState.held, CallState.transferring, CallState.ended, CallState.failed},
    CallState.held: {CallState.active, CallState.transferring, CallState.ended, CallState.failed},
    CallState.transferring: {CallState.active, CallState.held, CallState.ended, CallState.failed},
    CallState.ended: {},
    CallState.failed: {},
  };

  static bool isValidTransition(CallState from, CallState to) => from == to || (transitions[from]?.contains(to) ?? false);
}

// Fachada de alto nivel del motor PJSIP: comandos tipados y flujo de eventos.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'native_bindings.dart';

enum SipTransport { udp, tcp, tls }

class EngineEvent {
  EngineEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;

  int get callId => (data['call_id'] as num?)?.toInt() ?? -1;
  int get accId => (data['acc_id'] as num?)?.toInt() ?? -1;
  String str(String k) => data[k]?.toString() ?? '';
  int intv(String k) => (data[k] as num?)?.toInt() ?? 0;
  bool flag(String k) => data[k] == true;
}

class AccountParams {
  AccountParams({
    required this.displayName,
    required this.username,
    required this.password,
    required this.server,
    this.authUser,
    this.port = 0,
    this.transport = SipTransport.udp,
    this.domain,
    this.proxy,
    this.expires = 300,
    this.srtp = 0,
  });
  final String displayName, username, password, server;
  final String? authUser, domain, proxy;
  final int port, expires, srtp;
  final SipTransport transport;
}

class SipEngine {
  SipEngine._();
  static final SipEngine instance = SipEngine._();

  late final NativeEngine _n;
  NativeCallable<NxEventNative>? _callable;
  final _events = StreamController<EngineEvent>.broadcast();
  bool _started = false;

  Stream<EngineEvent> get events => _events.stream;
  bool get started => _started;

  /// Arranca la instancia única de PJSIP.
  bool start({int logLevel = 3, bool sipTrace = false, bool tlsVerify = false, String? caFile, String? stun}) {
    if (_started) return true;
    _n = NativeEngine.open();
    _callable = NativeCallable<NxEventNative>.listener(_onNativeEvent);

    final cfg = _n.alloc<NxEngineConfig>(sizeOf<NxEngineConfig>());
    final ca = _n.cstr(caFile), st = _n.cstr(stun);
    cfg.ref
      ..logLevel = logLevel
      ..sipTrace = sipTrace ? 1 : 0
      ..userAgent = nullptr
      ..tlsCaFile = ca
      ..tlsVerify = tlsVerify ? 1 : 0
      ..stunServer = st
      ..ecTailMs = -1
      ..nullAudio = 0;
    final r = _n.init(cfg, _callable!.nativeFunction);
    _n.free(ca);
    _n.free(st);
    _n.free(cfg);
    _started = r == 0;
    return _started;
  }

  void stop() {
    if (!_started) return;
    _n.shutdown();
    _started = false;
    _callable?.close();
    _callable = null;
  }

  void _onNativeEvent(Pointer<Uint8> p) {
    final s = _n.readCString(p);
    _n.nxFree(p);
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      _events.add(EngineEvent(m['type']?.toString() ?? '', m));
    } catch (_) {
      // evento mal formado: se ignora
    }
  }

  // ---- Cuentas ----

  int addAccount(AccountParams a) {
    final c = _n.alloc<NxAccountConfig>(sizeOf<NxAccountConfig>());
    final ptrs = <Pointer<Uint8>>[];
    Pointer<Uint8> s(String? v) {
      final p = (v == null || v.isEmpty) ? nullptr.cast<Uint8>() : _n.cstr(v);
      ptrs.add(p);
      return p;
    }

    final pwd = _n.cstr(a.password);
    c.ref
      ..displayName = s(a.displayName)
      ..username = s(a.username)
      ..authUser = s(a.authUser)
      ..password = pwd
      ..server = s(a.server)
      ..port = a.port
      ..transport = a.transport.index
      ..domain = s(a.domain)
      ..proxy = s(a.proxy)
      ..regExpires = a.expires
      ..srtp = a.srtp;
    final id = _n.accountAdd(c);
    _n.freeSecret(pwd);
    for (final p in ptrs) {
      _n.free(p);
    }
    _n.free(c);
    return id;
  }

  void removeAccount(int accId) => _n.accountRemove(accId);
  void register(int accId, {bool renew = true}) => _n.accountRegister(accId, renew ? 1 : 0);

  // ---- Llamadas ----

  int makeCall(int accId, String dest, {bool holdOthers = true}) {
    final d = _n.cstr(dest);
    final r = _n.callMake(accId, d, holdOthers ? 1 : 0);
    _n.free(d);
    return r;
  }

  int answer(int callId, {bool holdOthers = true}) => _n.callAnswer(callId, holdOthers ? 1 : 0);
  int reject(int callId) => _n.callReject(callId);
  int hangup(int callId) => _n.callHangup(callId);
  int hold(int callId) => _n.callHold(callId);
  int unhold(int callId, {bool holdOthers = true}) => _n.callUnhold(callId, holdOthers ? 1 : 0);
  int hangupAll() => _n.hangupAll();

  int dtmf(int callId, String digits) {
    final d = _n.cstr(digits);
    final r = _n.callDtmf(callId, d);
    _n.free(d);
    return r;
  }

  int transferBlind(int callId, String dest) {
    final d = _n.cstr(dest);
    final r = _n.callXferBlind(callId, d);
    _n.free(d);
    return r;
  }

  int transferAttended(int callId, int consultCallId) => _n.callXferAttended(callId, consultCallId);

  // ---- Audio ----

  Map<String, dynamic>? audioDevices() {
    final s = _n.takeString(_n.audioDevices());
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  int setAudioDevices(int capture, int playback) => _n.audioSetDevices(capture, playback);
  int setMute(bool m) => _n.audioSetMute(m ? 1 : 0);
  int setVolume({double speaker = -1, double mic = -1}) => _n.audioSetVolume(speaker, mic);
  int refreshAudio() => _n.audioRefresh();
  /// tone: 0 trino, 2 clásico, 3 suave. waiting = aviso de llamada en espera.
  int ringStart({bool waiting = false, int tone = 0}) => _n.ringStart(waiting ? 1 : tone);
  int ringStop() => _n.ringStop();

  // ---- Códecs ----

  List<Map<String, dynamic>> codecs() {
    final s = _n.takeString(_n.codecs());
    if (s == null) return [];
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  }

  int setCodecPriority(String id, int prio) {
    final p = _n.cstr(id);
    final r = _n.codecSetPriority(p, prio);
    _n.free(p);
    return r;
  }

  // ---- Red / diagnóstico ----

  int networkChanged() => _n.networkChanged();
  String? dumpState() => _n.takeString(_n.dumpState());

  // ---- Funciones avanzadas ----

  int setDnd(bool on) => _n.setDnd(on ? 1 : 0);

  int blfAdd(int accId, String target) {
    final t = _n.cstr(target);
    final r = _n.blfAdd(accId, t);
    _n.free(t);
    return r;
  }

  int blfRemove(int buddyId) => _n.blfRemove(buddyId);
  int blfRefresh(int buddyId) => _n.blfRefresh(buddyId);
  int confJoin() => _n.confJoin();
  int confSplit(int keepCallId) => _n.confSplit(keepCallId);

  int recStart(int callId, String path) {
    final p = _n.cstr(path);
    final r = _n.recStart(callId, p);
    _n.free(p);
    return r;
  }

  int recStop() => _n.recStop();

  Map<String, dynamic>? callStats(int callId) {
    final s = _n.takeString(_n.callStats(callId));
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  // ---- Cifrado de notas (AES-256 + HMAC, clave en el Llavero) ----

  String? seal(String plain) => _n.seal(plain);
  String? unseal(String sealed) => _n.unseal(sealed);

  // ---- Almacenamiento seguro ----

  bool secretSet(String k, String v) => _n.secretSet(k, v);
  String? secretGet(String k) => _n.secretGet(k);
  void secretDelete(String k) => _n.secretDelete(k);
}

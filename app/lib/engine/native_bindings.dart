// Enlace FFI con el motor nativo NORYXS (native/engine/include/noryxs_engine.h).
// Sin dependencias externas: memoria y cadenas gestionadas con malloc/free de libc.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// ---- Estructuras (mismo orden y tipos que en C) ----

final class NxEngineConfig extends Struct {
  @Int32()
  external int logLevel;
  @Int32()
  external int sipTrace;
  external Pointer<Uint8> userAgent;
  external Pointer<Uint8> tlsCaFile;
  @Int32()
  external int tlsVerify;
  external Pointer<Uint8> stunServer;
  @Int32()
  external int ecTailMs;
  @Int32()
  external int nullAudio;
}

final class NxAccountConfig extends Struct {
  external Pointer<Uint8> displayName;
  external Pointer<Uint8> username;
  external Pointer<Uint8> authUser;
  external Pointer<Uint8> password;
  external Pointer<Uint8> server;
  @Int32()
  external int port;
  @Int32()
  external int transport;
  external Pointer<Uint8> domain;
  external Pointer<Uint8> proxy;
  @Int32()
  external int regExpires;
  @Int32()
  external int srtp;
}

typedef NxEventNative = Void Function(Pointer<Uint8>);

/// Acceso de bajo nivel a las funciones C del motor.
class NativeEngine {
  NativeEngine._(this._lib) {
    _malloc = _libc.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
    _cfree = _libc.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
    _strlen = _libc.lookupFunction<IntPtr Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('strlen');

    init = _lib.lookupFunction<Int32 Function(Pointer<NxEngineConfig>, Pointer<NativeFunction<NxEventNative>>),
        int Function(Pointer<NxEngineConfig>, Pointer<NativeFunction<NxEventNative>>)>('nx_init');
    shutdown = _lib.lookupFunction<Void Function(), void Function()>('nx_shutdown');
    nxFree = _lib.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>('nx_free');
    accountAdd = _lib.lookupFunction<Int32 Function(Pointer<NxAccountConfig>), int Function(Pointer<NxAccountConfig>)>('nx_account_add');
    accountRemove = _i1('nx_account_remove');
    accountRegister = _i2('nx_account_register');
    callMake = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Int32), int Function(int, Pointer<Uint8>, int)>('nx_call_make');
    callAnswer = _i2('nx_call_answer');
    callReject = _i1('nx_call_reject');
    callHangup = _i1('nx_call_hangup');
    callHold = _i1('nx_call_hold');
    callUnhold = _i2('nx_call_unhold');
    callDtmf = _is('nx_call_dtmf');
    callXferBlind = _is('nx_call_xfer_blind');
    callXferAttended = _i2('nx_call_xfer_attended');
    hangupAll = _lib.lookupFunction<Int32 Function(), int Function()>('nx_hangup_all');
    audioDevices = _str0('nx_audio_devices');
    audioSetDevices = _i2('nx_audio_set_devices');
    audioSetMute = _i1('nx_audio_set_mute');
    audioSetVolume = _lib.lookupFunction<Int32 Function(Float, Float), int Function(double, double)>('nx_audio_set_volume');
    audioRefresh = _lib.lookupFunction<Int32 Function(), int Function()>('nx_audio_refresh_devices');
    ringStart = _i1('nx_ring_start');
    ringStop = _lib.lookupFunction<Int32 Function(), int Function()>('nx_ring_stop');
    codecs = _str0('nx_codecs');
    codecSetPriority = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int32), int Function(Pointer<Uint8>, int)>('nx_codec_set_priority');
    networkChanged = _lib.lookupFunction<Int32 Function(), int Function()>('nx_network_changed');
    dumpState = _str0('nx_dump_state');
    setDnd = _i1('nx_set_dnd');
    setDndAcc = _i2('nx_set_dnd_acc');
    blfAdd = _is('nx_blf_add');
    blfRemove = _i1('nx_blf_remove');
    blfRefresh = _i1('nx_blf_refresh');
    confJoin = _lib.lookupFunction<Int32 Function(), int Function()>('nx_conf_join');
    confSplit = _i1('nx_conf_split');
    recStart = _is('nx_rec_start');
    recStop = _lib.lookupFunction<Int32 Function(), int Function()>('nx_rec_stop');
    playStart = _lib.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('nx_play_start');
    playStop = _lib.lookupFunction<Int32 Function(), int Function()>('nx_play_stop');
    playPos = _lib.lookupFunction<Int32 Function(), int Function()>('nx_play_pos');
    playSeek = _i1('nx_play_seek');
    callStats = _lib.lookupFunction<Pointer<Uint8> Function(Int32), Pointer<Uint8> Function(int)>('nx_call_stats');
    _seal = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>)>('nx_seal');
    _unseal = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>)>('nx_unseal');
    _pinSeal = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>('nx_pin_seal');
    _pinUnseal = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>('nx_pin_unseal');
    _secretSet = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Pointer<Uint8>), int Function(Pointer<Uint8>, Pointer<Uint8>)>('nx_secret_set');
    _secretGet = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>)>('nx_secret_get');
    _secretDelete = _lib.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('nx_secret_delete');
    if (_lib.providesSymbol('nx_transcribe')) {
      _transcribe = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Int32),
          Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int)>('nx_transcribe');
    }
  }

  /// Transcripción local (whisper.cpp). null en plataformas sin ella (iOS).
  Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int)? _transcribe;
  bool get canTranscribe => _transcribe != null;

  /// Bloqueante (segundos): llamar desde un Isolate.
  String? transcribe(String wav, String model, {String lang = 'auto', int threads = 4}) {
    final fn = _transcribe;
    if (fn == null) return null;
    final w = cstr(wav), m = cstr(model), l = cstr(lang);
    try {
      return takeString(fn(w, m, l, threads));
    } finally {
      free(w);
      free(m);
      free(l);
    }
  }

  static NativeEngine? _instance;

  /// El motor está enlazado estáticamente dentro del ejecutable en macOS.
  /// En Windows/Linux se cargará la biblioteca dinámica junto al ejecutable.
  static NativeEngine open() {
    if (_instance != null) return _instance!;
    DynamicLibrary lib;
    if (Platform.isMacOS || Platform.isIOS) {
      lib = DynamicLibrary.process(); // enlazado estáticamente en el ejecutable
    } else {
      // Windows/Linux: biblioteca junto al ejecutable (ruta absoluta: no depende del
      // directorio de trabajo ni de LD_LIBRARY_PATH).
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final sep = Platform.pathSeparator;
      final path = Platform.isWindows ? '$exeDir${sep}noryxs_engine.dll' : '$exeDir${sep}lib${sep}libnoryxs_engine.so';
      lib = DynamicLibrary.open(File(path).existsSync() ? path : (Platform.isWindows ? 'noryxs_engine.dll' : 'libnoryxs_engine.so'));
    }
    return _instance = NativeEngine._(lib);
  }

  final DynamicLibrary _lib;
  static final DynamicLibrary _libc = Platform.isWindows ? DynamicLibrary.open('ucrtbase.dll') : DynamicLibrary.process();

  late final Pointer<Void> Function(int) _malloc;
  late final void Function(Pointer<Void>) _cfree;
  late final int Function(Pointer<Uint8>) _strlen;

  late final int Function(Pointer<NxEngineConfig>, Pointer<NativeFunction<NxEventNative>>) init;
  late final void Function() shutdown;
  late final void Function(Pointer<Uint8>) nxFree;
  late final int Function(Pointer<NxAccountConfig>) accountAdd;
  late final int Function(int) accountRemove;
  late final int Function(int, int) accountRegister;
  late final int Function(int, Pointer<Uint8>, int) callMake;
  late final int Function(int, int) callAnswer;
  late final int Function(int) callReject;
  late final int Function(int) callHangup;
  late final int Function(int) callHold;
  late final int Function(int, int) callUnhold;
  late final int Function(int, Pointer<Uint8>) callDtmf;
  late final int Function(int, Pointer<Uint8>) callXferBlind;
  late final int Function(int, int) callXferAttended;
  late final int Function() hangupAll;
  late final Pointer<Uint8> Function() audioDevices;
  late final int Function(int, int) audioSetDevices;
  late final int Function(int) audioSetMute;
  late final int Function(double, double) audioSetVolume;
  late final int Function() audioRefresh;
  late final int Function(int) ringStart;
  late final int Function() ringStop;
  late final Pointer<Uint8> Function() codecs;
  late final int Function(Pointer<Uint8>, int) codecSetPriority;
  late final int Function() networkChanged;
  late final Pointer<Uint8> Function() dumpState;
  late final int Function(int) setDnd;
  late final int Function(int, int) setDndAcc;
  late final int Function(int, Pointer<Uint8>) blfAdd;
  late final int Function(int) blfRemove;
  late final int Function(int) blfRefresh;
  late final int Function() confJoin;
  late final int Function(int) confSplit;
  late final int Function(int, Pointer<Uint8>) recStart;
  late final int Function() recStop;
  late final int Function(Pointer<Uint8>) playStart;
  late final int Function() playStop;
  late final int Function() playPos;
  late final int Function(int) playSeek;
  late final Pointer<Uint8> Function(int) callStats;
  late final Pointer<Uint8> Function(Pointer<Uint8>) _seal;
  late final Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>) _pinSeal;
  late final Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>) _pinUnseal;
  late final Pointer<Uint8> Function(Pointer<Uint8>) _unseal;
  late final int Function(Pointer<Uint8>, Pointer<Uint8>) _secretSet;
  late final Pointer<Uint8> Function(Pointer<Uint8>) _secretGet;
  late final int Function(Pointer<Uint8>) _secretDelete;

  int Function(int) _i1(String n) => _lib.lookupFunction<Int32 Function(Int32), int Function(int)>(n);
  int Function(int, int) _i2(String n) => _lib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(n);
  int Function(int, Pointer<Uint8>) _is(String n) =>
      _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>(n);
  Pointer<Uint8> Function() _str0(String n) => _lib.lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(n);

  // ---- Memoria ----

  Pointer<T> alloc<T extends NativeType>(int bytes) {
    final p = _malloc(bytes).cast<Uint8>();
    p.asTypedList(bytes).fillRange(0, bytes, 0);
    return p.cast<T>();
  }

  void free(Pointer p) {
    if (p.address != 0) _cfree(p.cast<Void>());
  }

  /// Cadena C (UTF-8, terminada en 0). Liberar con [free] o [freeSecret].
  Pointer<Uint8> cstr(String? s) {
    if (s == null) return nullptr;
    final bytes = utf8.encode(s);
    final p = alloc<Uint8>(bytes.length + 1);
    p.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return p;
  }

  /// Sobrescribe con ceros antes de liberar (contraseñas).
  void freeSecret(Pointer<Uint8> p) {
    if (p.address == 0) return;
    final n = _strlen(p);
    p.asTypedList(n).fillRange(0, n, 0);
    free(p);
  }

  String readCString(Pointer<Uint8> p) {
    if (p.address == 0) return '';
    final n = _strlen(p);
    return utf8.decode(Uint8List.fromList(p.asTypedList(n)), allowMalformed: true);
  }

  /// Lee una cadena devuelta por el motor y la libera con nx_free.
  String? takeString(Pointer<Uint8> p) {
    if (p.address == 0) return null;
    final s = readCString(p);
    nxFree(p);
    return s;
  }

  // ---- Cifrado de datos locales ----

  String? seal(String plain) {
    final p = cstr(plain);
    try {
      return takeString(_seal(p));
    } finally {
      freeSecret(p);
    }
  }

  /// Cifra con un PIN (paquetes de configuración de puestos).
  String? pinSeal(String plain, String pin) {
    final p = cstr(plain), k = cstr(pin);
    try {
      return takeString(_pinSeal(p, k));
    } finally {
      freeSecret(p);
      freeSecret(k);
    }
  }

  /// null si el PIN es incorrecto o el paquete está manipulado.
  String? pinUnseal(String sealed, String pin) {
    final p = cstr(sealed), k = cstr(pin);
    try {
      return takeString(_pinUnseal(p, k));
    } finally {
      free(p);
      freeSecret(k);
    }
  }

  String? unseal(String sealed) {
    final p = cstr(sealed);
    try {
      return takeString(_unseal(p));
    } finally {
      free(p);
    }
  }

  // ---- Llavero ----

  bool secretSet(String key, String value) {
    final k = cstr(key), v = cstr(value);
    try {
      return _secretSet(k, v) == 0;
    } finally {
      free(k);
      freeSecret(v);
    }
  }

  String? secretGet(String key) {
    final k = cstr(key);
    try {
      final p = _secretGet(k);
      if (p.address == 0) return null;
      final s = readCString(p);
      final n = _strlen(p);
      p.asTypedList(n).fillRange(0, n, 0);
      nxFree(p);
      return s;
    } finally {
      free(k);
    }
  }

  void secretDelete(String key) {
    final k = cstr(key);
    _secretDelete(k);
    free(k);
  }
}

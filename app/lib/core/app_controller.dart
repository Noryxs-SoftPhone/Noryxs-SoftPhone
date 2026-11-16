// Punto de unión: arranca el motor y conecta todos los gestores.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';
import 'call_managers.dart';
import 'feature_managers.dart';
import 'models.dart';
import 'phone_info.dart';
import 'queue_manager.dart';
import 'sip_managers.dart';
import 'storage.dart';
import 'support_managers.dart';

class AppController {
  AppController._();
  static final AppController I = AppController._();

  final SipEngine engine = SipEngine.instance;
  late final AppStorage storage;
  late final SipAccountManager accounts;
  late final MultiLineManager lines;
  late final SipRegistrationManager registration;
  late final CallSessionManager calls;
  late final CallTransferManager transfers;
  late final DtmfManager dtmf;
  late final AudioDeviceManager audio;
  late final ContactManager contacts;
  late final CallHistoryManager history;
  late final NotificationManager notifications;
  late final VoicemailManager voicemail;
  late final BlfManager blf;
  late final PbxFeatureManager features;
  late final QueueManager queue;

  /// Avisos breves en la parte inferior del terminal.
  final ValueNotifier<String?> toast = ValueNotifier(null);
  Timer? _toastTimer;

  void showToast(String msg) {
    toast.value = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () => toast.value = null);
  }

  String? startupError;
  StreamSubscription<EngineEvent>? _sub;

  /// Todo lo que la interfaz necesita escuchar.
  late final Listenable all;

  /// Registro de arranque (diagnóstico): Application Support/NORYXS/startup.log
  final _boot = StringBuffer();
  IOSink? _engineLog;

  /// engine.log en la carpeta de datos (se rota a engine.log.1 al pasar de 5 MB).
  void _openEngineLog() {
    try {
      final sep = Platform.pathSeparator;
      final f = File('${storage.dir.path}${sep}engine.log');
      if (f.existsSync() && f.lengthSync() > 5 * 1024 * 1024) f.renameSync('${f.path}.1');
      _engineLog = f.openWrite(mode: FileMode.append)..writeln('==== ${DateTime.now().toIso8601String()} arranque ====');
    } catch (_) {}
  }

  void step(String s) {
    _boot.writeln('${DateTime.now().toIso8601String()} $s');
    try {
      File('${storage.dir.path}${Platform.pathSeparator}startup.log').writeAsStringSync(_boot.toString(), flush: true);
    } catch (_) {}
  }

  Future<void> init() async {
    storage = await AppStorage.open();
    step('storage ok (${Platform.operatingSystem})');
    // Windows/Linux: registro de diagnóstico con trazas SIP (sin contraseñas) en engine.log
    final diag = Platform.isWindows || Platform.isLinux;
    if (diag) _openEngineLog();
    final started = engine.start(logLevel: kDebugMode || diag ? 4 : 2, sipTrace: diag);
    step('engine.start -> $started');
    if (!started) {
      startupError = 'No se pudo iniciar el motor PJSIP';
    }

    accounts = SipAccountManager(storage, engine);
    lines = MultiLineManager();
    registration = SipRegistrationManager(engine, accounts, lines);
    calls = CallSessionManager(engine, lines);
    transfers = CallTransferManager(engine, calls, lines);
    dtmf = DtmfManager(engine, calls);
    audio = AudioDeviceManager(engine, storage);
    contacts = ContactManager(storage);
    history = CallHistoryManager(storage, engine);
    notifications = NotificationManager(engine, storage);
    voicemail = VoicemailManager();
    blf = BlfManager(engine, storage, lines, calls);
    features = PbxFeatureManager(engine, storage, lines, calls);
    queue = QueueManager(engine, storage);
    all = Listenable.merge([accounts, lines, calls, audio, contacts, history, notifications, voicemail, blf, features, queue]);

    step('managers creados');
    await Future.wait([accounts.load(), audio.load(), contacts.load(), history.load(), blf.load(), features.load(), queue.load()]);
    step('datos cargados');
    lines.sync(accounts.accounts);

    calls.contactLookup = contacts.lookup;
    calls.onCallEnded = (c) => history.add(c, calls.lineOf(c));
    // "Atender" desde el panel de cola: la llamada llega a nuestra extensión y se contesta sola
    calls.onIncoming = (c) {
      if (queue.consumePendingPickup(c.remoteNumber)) {
        Future.microtask(() => calls.answer(c));
      }
    };
    calls.addListener(() => notifications.update(calls.calls));
    notifications.onWake = registration.networkChanged;
    notifications.describeLine = (c) {
      final l = calls.lineOf(c);
      return l == null ? '' : 'Línea ${l.number} (${l.extension})';
    };
    notifications.callerContext = (c) {
      final last = history.lastContextFor(c.remoteNumber);
      return (
        geo: PhoneNumbers.lookup(c.remoteNumber)?.display ?? '',
        lastNote: last == null ? '' : last.note.trim().replaceAll('\n', ' '),
      );
    };
    notifications.onAnswerFromNotification = (id) {
      final c = calls.byId(id);
      if (c != null) calls.answer(c);
    };
    notifications.onRejectFromNotification = (id) {
      final c = calls.byId(id);
      if (c != null) calls.reject(c);
    };
    notifications.onSilenceFromNotification = (id) {
      final c = calls.byId(id);
      if (c != null) calls.silenceRing(c);
    };
    step('antes de notifications.init');
    await notifications.init().timeout(const Duration(seconds: 3), onTimeout: () => step('notifications.init timeout'));
    step('notifications ok');

    _sub = engine.events.listen((e) {
      switch (e.type) {
        case 'reg':
          registration.onEvent(e);
        case 'incoming' || 'call' || 'xfer' || 'replaced' || 'dnd_rejected' || 'conf' || 'rec':
          calls.onEvent(e);
          if (e.type == 'rec' && !e.flag('recording') && calls.lastRecordingPath != null) {
            showToast('Grabación guardada en Documentos/NORYXS Grabaciones');
          }
          if (e.type == 'dnd_rejected') {
            showToast('No molestar: llamada de ${e.str('remote_number').isEmpty ? 'número oculto' : e.str('remote_number')} rechazada');
          }
        case 'mwi':
          voicemail.onEvent(e);
        case 'blf':
          blf.onEvent(e);
        case 'log':
          if (kDebugMode && e.intv('level') <= 3) debugPrint('[pjsip] ${e.str('msg').trimRight()}');
          _engineLog?.writeln(e.str('msg').trimRight());
      }
    });

    if (engine.started) {
      audio.applyAll();
      step('audio ok');
      registration.applyAll();
      step('registro lanzado');
    }
    step('init completo');
  }

  /// Guarda una cuenta (contraseña al Llavero) y repite el registro.
  Future<bool> saveAccount(SipLine line, {String? password}) async {
    final ok = await accounts.update(line.account, newPassword: password);
    lines.sync(accounts.accounts);
    registration.apply(line);
    return ok;
  }

  Future<void> addLine() async {
    final a = await accounts.addLine();
    if (a != null) lines.sync(accounts.accounts);
  }

  Future<void> removeLine(SipLine line) async {
    if (line.accId >= 0) engine.removeAccount(line.accId);
    await accounts.removeLine(line.account);
    lines.sync(accounts.accounts);
  }

  /// Llama al buzón (*97) por la línea indicada.
  void dialVoicemail(SipLine line) {
    if (calls.makeCall(line, '*97') != null) showToast('Llamando al buzón de ${line.label} (*97)');
  }

  void dispose() {
    _sub?.cancel();
    queue.disconnect();
    engine.stop();
  }

  RegState get overallReg {
    final configured = lines.lines.where((l) => l.account.isComplete && l.account.enabled).toList();
    if (configured.isEmpty) return RegState.unregistered;
    if (configured.every((l) => l.reg == RegState.registered)) return RegState.registered;
    if (configured.any((l) => l.reg == RegState.registered)) return RegState.registering;
    return configured.first.reg;
  }
}

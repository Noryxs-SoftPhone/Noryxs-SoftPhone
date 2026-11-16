// Punto de unión: arranca el motor y conecta todos los gestores.
import 'dart:async';
import 'i18n.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../engine/sip_engine.dart';
import 'call_managers.dart';
import 'feature_managers.dart';
import 'models.dart';
import 'dial_url.dart';
import 'playback.dart';
import 'provisioning.dart';
import 'updates.dart';
import 'whatsapp.dart';
import 'phone_info.dart';
import 'queue_manager.dart';
import 'sip_managers.dart';
import 'storage.dart';
import 'transcription.dart';
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
  late final PlaybackManager playback;
  late final WhatsAppManager whatsapp;
  late final UpdateManager updates;
  late final TranscriptionManager transcripts;

  /// Para abrir diálogos desde fuera de la interfaz (enlaces noryxs:provision).
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Abre la importación de configuración con el paquete recibido (lo registra la interfaz).
  void Function(String sealed)? onProvisionLink;

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
      startupError = tr('No se pudo iniciar el motor PJSIP');
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
    playback = PlaybackManager(engine);
    whatsapp = WhatsAppManager(storage);
    updates = UpdateManager(storage);
    transcripts = TranscriptionManager(storage, engine);
    all = Listenable.merge([accounts, lines, calls, audio, contacts, history, notifications, voicemail, blf, features, queue, playback, updates, transcripts]);

    step('managers creados');
    await Future.wait([accounts.load(), audio.load(), contacts.load(), history.load(), blf.load(), features.load(), queue.load(), whatsapp.load(), updates.load()]);
    step('datos cargados');
    lines.sync(accounts.accounts);
    transcripts.hasActiveCall = () => calls.liveCalls.isNotEmpty;
    queue.lineQueues = () => [for (final l in lines.lines) if (l.account.enabled) ...l.account.queues];
    unawaited(transcripts.load(history.entries));

    calls.contactLookup = nameFor;
    calls.onCallEnded = (c) {
      history.add(c, calls.lineOf(c));
      transcripts.enqueue(c.recordings);
    };
    // "Atender" desde el panel de cola: la llamada llega a nuestra extensión y se contesta sola
    calls.onIncoming = (c) {
      playback.stop(); // una llamada entrante corta la reproducción
      if (queue.consumePendingPickup(c.remoteNumber)) {
        Future.microtask(() => calls.answer(c));
      }
    };
    calls.addListener(() => notifications.update(calls.calls));
    notifications.onWake = registration.networkChanged;
    notifications.describeLine = (c) {
      final l = calls.lineOf(c);
      return l == null ? '' : tr('Línea {0} ({1})', [l.number, l.extension]);
    };
    notifications.toneFor = (c) => calls.lineOf(c)?.account.ringTone ?? -1;
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
    notifications.onOpenUrl = (u) {
      if (u.startsWith('noryxs:provision')) {
        final p = Provisioning.extract(u);
        if (p != null) onProvisionLink?.call(p);
      } else if (u.startsWith('noryxs:')) {
        handleHotkey(u.substring(11));
      } else {
        dialFromUrl(u);
      }
    };
    notifications.onHotkey = handleHotkey;
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
            showToast(tr('Grabación guardada en Documentos/NORYXS Grabaciones'));
          }
          if (e.type == 'dnd_rejected') {
            showToast(tr('No molestar: llamada de {0} rechazada', [e.str('remote_number').isEmpty ? 'número oculto' : e.str('remote_number')]));
          }
        case 'play':
          playback.onEnded();
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
  /// Nombre a mostrar para un número según la agenda ('' si no está; la centralita envía el suyo).
  String nameFor(String number) => contacts.lookup(number);

  /// Atajos globales y botón de los cascos.
  ///   answer  → contesta la llamada que suena
  ///   hangup  → cuelga la llamada en curso (o rechaza la que suena si no hay otra)
  ///   mute    → silencia / activa el micrófono
  ///   headset → contesta si suena; si no, cuelga
  void handleHotkey(String action) {
    final ringing = calls.liveCalls.where((c) => c.state == CallState.incoming).firstOrNull;
    final f = calls.focused;
    final talking = (f != null && f.state.isLive && f.state != CallState.incoming)
        ? f
        : calls.liveCalls.where((c) => c.state != CallState.incoming).firstOrNull;
    switch (action) {
      case 'answer':
        if (ringing != null) calls.answer(ringing);
      case 'hangup':
        if (talking != null) {
          calls.hangup(talking);
        } else if (ringing != null) {
          calls.reject(ringing);
        }
      case 'mute':
        if (talking != null) {
          calls.setMute(!calls.muted);
          showToast(calls.muted ? tr('Micrófono silenciado') : tr('Micrófono activado'));
        }
      case 'headset':
        if (ringing != null) {
          calls.answer(ringing);
        } else if (talking != null) {
          calls.hangup(talking);
        }
    }
  }

  /// Clic para llamar (tel:/sip:/callto:): marca por la línea seleccionada, o por la
  /// primera registrada. Si la app acaba de arrancar, espera a que alguna línea registre.
  Future<void> dialFromUrl(String url) async {
    final number = parseDialUrl(url);
    if (number == null) {
      showToast(tr('El enlace no contiene un número para llamar'));
      return;
    }
    SipLine? pick() {
      if (lines.lines.isEmpty) return null;
      final sel = lines.selectedLine;
      if (sel.reg == RegState.registered) return sel;
      return lines.lines.where((l) => l.reg == RegState.registered).firstOrNull;
    }

    var line = pick();
    for (var i = 0; line == null && i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      line = pick();
    }
    if (line == null) {
      showToast(tr('No hay ninguna línea registrada para llamar a {0}', [number]));
      return;
    }
    if (calls.makeCall(line, number) == null) {
      showToast(calls.lastError ?? tr('No se pudo llamar a {0}', [number]));
    } else {
      showToast(tr('Llamando a {0} por {1}', [number, line.label.replaceFirst('LÍNEA', 'Línea')]));
    }
  }

  Future<bool> saveAccount(SipLine line, {String? password}) async {
    final ok = await accounts.update(line.account, newPassword: password);
    lines.sync(accounts.accounts);
    registration.apply(line);
    queue.refreshQueues();
    return ok;
  }

  /// Línea que atiende una cola: la primera línea activa que la tenga asignada;
  /// si ninguna, la seleccionada.
  SipLine lineForQueue(String queueNumber) {
    for (final l in lines.lines) {
      if (l.account.enabled && l.account.queues.contains(queueNumber)) return l;
    }
    return lines.selectedLine;
  }

  /// true si la cola tiene una línea asignada (no depende de la seleccionada).
  bool queueHasLine(String queueNumber) => lines.lines.any((l) => l.account.enabled && l.account.queues.contains(queueNumber));

  Future<void> addLine() async {
    final a = await accounts.addLine();
    if (a != null) lines.sync(accounts.accounts);
  }

  Future<void> removeLine(SipLine line) async {
    if (line.accId >= 0) engine.removeAccount(line.accId);
    await accounts.removeLine(line.account);
    lines.sync(accounts.accounts);
    queue.refreshQueues();
  }

  /// Llama al buzón (*97) por la línea indicada.
  void dialVoicemail(SipLine line) {
    if (calls.makeCall(line, '*97') != null) showToast(tr('Llamando al buzón de {0} (*97)', [line.label]));
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

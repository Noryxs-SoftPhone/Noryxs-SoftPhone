// Audio, códecs, agenda, historial y avisos.
import 'feature_managers.dart';
import 'i18n.dart';
import 'search.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/sip_engine.dart';
import 'models.dart';
import 'phone_info.dart';
import 'sip_managers.dart';
import 'storage.dart';

class AudioDevice {
  AudioDevice(this.id, this.name, this.inputs, this.outputs);
  final int id;
  final String name;
  final int inputs, outputs;
}

/// Dispositivos de audio, volumen y códecs (PJSIP aplica los códecs a todas las líneas).
class AudioDeviceManager extends ChangeNotifier {
  AudioDeviceManager(this._engine, this._storage);
  final SipEngine _engine;
  final AppStorage _storage;
  static const _file = 'settings.json';

  List<AudioDevice> devices = [];
  String? captureName; // null = predeterminado del sistema
  String? playbackName;
  double speakerVolume = 1.0;
  double micVolume = 1.0;

  /// Orden y activación de códecs. Ids PJSIP.
  List<MapEntry<String, bool>> codecs = [
    const MapEntry('G722/16000/1', true),
    const MapEntry('opus/48000/2', true),
    MapEntry('PCMA/8000/1', true),
    MapEntry('PCMU/8000/1', true),
  ];

  static String codecLabel(String id) => switch (id.split('/').first.toUpperCase()) {
        'G722' => 'G.722 (HD)',
        'OPUS' => tr('Opus'),
        'PCMA' => tr('G.711 A-law'),
        'PCMU' => tr('G.711 µ-law'),
        final s => s,
      };

  String get preferredCodecLabel {
    final first = codecs.where((c) => c.value).map((c) => c.key).firstOrNull;
    return first == null ? '—' : codecLabel(first).replaceAll(' (HD)', ' HD');
  }

  Future<void> load() async {
    final s = await _storage.read(_file);
    if (s is Map<String, dynamic>) {
      captureName = s['capture'] as String?;
      playbackName = s['playback'] as String?;
      speakerVolume = (s['speaker'] as num?)?.toDouble() ?? 1.0;
      micVolume = (s['mic'] as num?)?.toDouble() ?? 1.0;
      final cl = s['codecs'];
      if (cl is List) {
        final loaded = [for (final c in cl.cast<Map<String, dynamic>>()) MapEntry(c['id'] as String, c['on'] as bool? ?? true)];
        if (loaded.isNotEmpty) codecs = loaded;
      }
    }
  }

  Future<void> _save() => _storage.write(_file, {
        'capture': captureName,
        'playback': playbackName,
        'speaker': speakerVolume,
        'mic': micVolume,
        'codecs': [for (final c in codecs) {'id': c.key, 'on': c.value}],
      });

  /// Aplica la configuración guardada al motor.
  void applyAll() {
    refresh();
    _applyDevices();
    _engine.setVolume(speaker: speakerVolume, mic: micVolume);
    _applyCodecs();
  }

  void refresh() {
    _engine.refreshAudio();
    final d = _engine.audioDevices();
    devices = [
      for (final m in (d?['devices'] as List? ?? []).cast<Map<String, dynamic>>())
        AudioDevice((m['id'] as num).toInt(), m['name'] as String, (m['inputs'] as num).toInt(), (m['outputs'] as num).toInt())
    ];
    notifyListeners();
  }

  List<AudioDevice> get inputs => devices.where((d) => d.inputs > 0).toList();
  List<AudioDevice> get outputs => devices.where((d) => d.outputs > 0).toList();

  int _idOf(String? name, bool input) {
    if (name == null) return -1;
    for (final d in devices) {
      if (d.name == name && (input ? d.inputs > 0 : d.outputs > 0)) return d.id;
    }
    return -1; // desconectado → predeterminado
  }

  void _applyDevices() => _engine.setAudioDevices(_idOf(captureName, true), _idOf(playbackName, false));

  Future<void> setDevices({String? capture, String? playback}) async {
    captureName = capture;
    playbackName = playback;
    _applyDevices();
    notifyListeners();
    await _save();
  }

  Future<void> setVolumes({double? speaker, double? mic}) async {
    if (speaker != null) speakerVolume = speaker;
    if (mic != null) micVolume = mic;
    _engine.setVolume(speaker: speakerVolume, mic: micVolume);
    notifyListeners();
    await _save();
  }

  void _applyCodecs() {
    var prio = 254;
    for (final c in codecs) {
      _engine.setCodecPriority(c.key, c.value ? prio-- : 0);
    }
  }

  Future<void> setCodecs(List<MapEntry<String, bool>> list) async {
    codecs = list;
    _applyCodecs();
    notifyListeners();
    await _save();
  }

  /// Nombre corto del dispositivo de salida para la cabecera.
  String get outputLabel {
    final n = playbackName ?? tr('Audio');
    if (n.toLowerCase().contains('usb')) return tr('USB Audio');
    return n.length > 16 ? '${n.substring(0, 15)}…' : n;
  }
}

/// Agenda local.
class ContactManager extends ChangeNotifier {
  ContactManager(this._storage);
  final AppStorage _storage;
  static const _file = 'contacts.json';
  final List<Contact> contacts = [];

  Future<void> load() async {
    final d = await _storage.read(_file);
    contacts.clear();
    if (d is List) contacts.addAll(d.cast<Map<String, dynamic>>().map(Contact.fromJson));
    notifyListeners();
  }

  Future<void> _save() async {
    await _storage.write(_file, contacts.map((c) => c.toJson()).toList());
    notifyListeners();
  }

  List<Contact> search(String q) {
    final list = contacts
        .where((c) => matchesQuery(q, texts: [c.name, c.company, c.number], numbers: [c.number]))
        .toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  static String _digits(String n) => n.replaceAll(RegExp(r'[^0-9+*#]'), '');

  String lookup(String number) {
    final n = _digits(number);
    if (n.isEmpty) return '';
    for (final c in contacts) {
      final cn = _digits(c.number);
      if (cn == n || (n.length > 6 && cn.endsWith(n.substring(n.length - 7)))) return c.name;
    }
    return '';
  }

  Future<void> upsert(Contact c) async {
    final i = contacts.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      contacts[i] = c;
    } else {
      contacts.add(c);
    }
    await _save();
  }

  Future<void> remove(Contact c) async {
    contacts.removeWhere((x) => x.id == c.id);
    await _save();
  }

  Future<void> toggleFavorite(Contact c) async {
    c.favorite = !c.favorite;
    await _save();
  }

  Contact create({String name = '', String number = ''}) => Contact(id: newId(), name: name, number: number);
}

/// Historial de llamadas, con nota rápida y etiquetas por registro.
///
/// La nota y las etiquetas se guardan **cifradas** (AES-256 + HMAC, clave en el
/// Llavero) en notes.json; history.json solo contiene los metadatos.
class CallHistoryManager extends ChangeNotifier {
  CallHistoryManager(this._storage, this._engine);
  final AppStorage _storage;
  final SipEngine _engine;
  static const _file = 'history.json';
  static const _notesFile = 'notes.json';
  static const _tagsFile = 'tags.json';
  static const _max = 500;
  static const maxNote = 280;
  final List<HistoryEntry> entries = [];

  /// Perdidas marcadas a mano como atendidas (ids), aunque no se hayan devuelto desde aquí.
  final Set<String> _pendingDone = {};
  static const _pendingFile = 'pending_done.json';

  /// Perdidas pendientes de devolver: la última llamada con ese número es una perdida
  /// (no se devolvió ni se volvió a hablar con él después) y no se marcó como atendida.
  /// Una por número, la más reciente.
  List<HistoryEntry> get pendingMissed {
    final seen = <String>[];
    final out = <HistoryEntry>[];
    for (final e in entries) {
      if (e.number.isEmpty || seen.any((n) => PhoneNumbers.same(n, e.number))) continue;
      seen.add(e.number);
      if (e.type == HistoryType.missed && !_pendingDone.contains(e.id)) out.add(e);
    }
    return out;
  }

  bool isPending(HistoryEntry e) => pendingMissed.any((p) => p.id == e.id);

  Future<void> markHandled(HistoryEntry e) async {
    _pendingDone.add(e.id);
    notifyListeners();
    await _storage.write(_pendingFile, _pendingDone.toList());
  }

  /// Las 4 etiquetas (nombres configurables).
  final List<CallTag> tags = [
    CallTag(id: 't1', label: tr('Presupuesto'), color: 'gold'),
    CallTag(id: 't2', label: tr('Urgente'), color: 'red'),
    CallTag(id: 't3', label: tr('Devolver llamada'), color: 'sky'),
    CallTag(id: 't4', label: tr('Resuelto'), color: 'green'),
  ];

  CallTag? tagById(String id) => tags.where((t) => t.id == id).firstOrNull;

  /// Enlaza con su llamada las grabaciones que aún no lo están (versiones anteriores):
  /// el nombre del WAV lleva fecha, hora y número (AAAA-MM-DD_HHMMSS_L1_numero.wav).
  bool _linkOrphanRecordings() {
    final dir = Directory(recordingsDir());
    if (!dir.existsSync()) return false;
    final linked = <String>{for (final e in entries) ...e.recordings};
    final re = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})_L\d+_([^.]*)\.wav$');
    var changed = false;
    for (final f in dir.listSync().whereType<File>()) {
      if (linked.contains(f.path)) continue;
      final m = re.firstMatch(f.path);
      if (m == null) continue;
      final t = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
      final who = m[7]!;
      for (final e in entries) {
        final num = e.number.replaceAll(RegExp(r'[^0-9A-Za-z+]'), '');
        final end = e.start.add(Duration(seconds: e.durationSec + 90));
        if ((num == who || (num.isEmpty && who == 'oculto')) && !t.isBefore(e.start.subtract(const Duration(seconds: 5))) && t.isBefore(end)) {
          e.recordings.add(f.path);
          changed = true;
          break;
        }
      }
    }
    return changed;
  }

  Future<void> load() async {
    final pd = await _storage.read(_pendingFile);
    if (pd is List) _pendingDone.addAll(pd.whereType<String>());
    final d = await _storage.read(_file);
    entries.clear();
    if (d is List) entries.addAll(d.cast<Map<String, dynamic>>().map(HistoryEntry.fromJson));
    if (_linkOrphanRecordings()) await _saveEntries();
    final t = await _storage.read(_tagsFile);
    if (t is Map<String, dynamic>) {
      for (final tag in tags) {
        final l = t[tag.id];
        if (l is String && l.trim().isNotEmpty) tag.label = l.trim();
      }
    }
    // Notas cifradas
    final n = await _storage.read(_notesFile);
    if (n is Map<String, dynamic>) {
      for (final e in entries) {
        final sealed = n[e.id];
        if (sealed is! String) continue;
        final plain = _engine.unseal(sealed);
        if (plain == null) continue; // manipulada o clave distinta: se ignora
        try {
          final m = jsonDecode(plain) as Map<String, dynamic>;
          e.note = m['note'] as String? ?? '';
          e.tags = (m['tags'] as List?)?.map((x) => x.toString()).toList() ?? [];
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> _saveEntries() => _storage.write(_file, entries.map((e) => e.toJson()).toList());

  Future<void> _saveNotes() async {
    final out = <String, String>{};
    for (final e in entries) {
      if (!e.hasContext) continue;
      final sealed = _engine.seal(jsonEncode({'note': e.note, 'tags': e.tags}));
      if (sealed != null) out[e.id] = sealed;
    }
    await _storage.write(_notesFile, out);
  }

  Future<void> add(CallSession c, SipLine? line) async {
    final type = c.incoming ? (c.wasAnswered ? HistoryType.incoming : HistoryType.missed) : HistoryType.outgoing;
    entries.insert(
      0,
      HistoryEntry(
        type: type,
        number: c.remoteNumber,
        name: c.contactName.isNotEmpty ? c.contactName : c.remoteName,
        lineNumber: line?.number ?? 0,
        extension: line?.extension ?? '',
        start: c.createdAt,
        durationSec: c.duration.inSeconds,
        note: c.note.trim(),
        tags: List.of(c.tags),
        recordings: List.of(c.recordings),
      ),
    );
    if (entries.length > _max) entries.removeRange(_max, entries.length);
    notifyListeners();
    await _saveEntries();
    if (c.note.trim().isNotEmpty || c.tags.isNotEmpty) await _saveNotes();
  }

  Timer? _noteDebounce;

  /// Nota de un registro (se guarda cifrada con un pequeño retardo mientras se escribe).
  void setNote(HistoryEntry e, String text) {
    e.note = text.length > maxNote ? text.substring(0, maxNote) : text;
    notifyListeners();
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 600), _saveNotes);
  }

  Future<void> toggleTag(HistoryEntry e, String tagId) async {
    e.tags.contains(tagId) ? e.tags.remove(tagId) : e.tags.add(tagId);
    notifyListeners();
    await _saveNotes();
  }

  Future<void> renameTags(Map<String, String> labels) async {
    for (final t in tags) {
      final l = labels[t.id];
      if (l != null && l.trim().isNotEmpty) t.label = l.trim();
    }
    notifyListeners();
    await _storage.write(_tagsFile, {for (final t in tags) t.id: t.label});
  }

  Future<void> clear() async {
    entries.clear();
    notifyListeners();
    await _storage.write(_file, []);
    await _storage.write(_notesFile, {}); // las notas se borran con el historial
  }

  int get missedCount => entries.where((e) => e.type == HistoryType.missed).length;

  /// Último registro de ese número con nota o etiquetas (para mostrarlo antes de descolgar).
  HistoryEntry? lastContextFor(String number) {
    if (number.trim().isEmpty) return null;
    for (final e in entries) {
      if (e.hasContext && PhoneNumbers.same(e.number, number)) return e;
    }
    return null;
  }

  /// Texto de comprobante para copiar al portapapeles.
  String summary(HistoryEntry e, {String contactName = ''}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = e.start;
    final date = '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    final arrow = switch (e.type) { HistoryType.outgoing => '→', HistoryType.incoming => '←', HistoryType.missed => '✕' };
    final who = contactName.isNotEmpty ? '$contactName (${e.number})' : (e.name.isNotEmpty && e.name != e.number ? '${e.name} (${e.number})' : e.number);
    final dur = Duration(seconds: e.durationSec);
    final durTxt = '${two(dur.inMinutes)}:${two(dur.inSeconds % 60)}';
    final kind = switch (e.type) { HistoryType.outgoing => tr('Saliente'), HistoryType.incoming => tr('Entrante'), HistoryType.missed => tr('Perdida') };
    final b = StringBuffer(tr('[NORYXS SIP] {0} • Ext. {1} {2} {3} ({4} · Duración: {5})', [date, e.extension.isEmpty ? '-' : e.extension, arrow, who, kind, durTxt]));
    final tagNames = e.tags.map((id) => tagById(id)?.label).whereType<String>().toList();
    if (tagNames.isNotEmpty) b.write(tr(' | Etiquetas: {0}', [tagNames.join(', ')]));
    if (e.note.trim().isNotEmpty) b.write(tr(' | Nota: {0}', [e.note.trim().replaceAll('\n', ' ')]));
    return b.toString();
  }
}

/// Avisos de llamada entrante: timbre, ventana al frente y notificación del sistema.
///
/// El aviso principal es la propia ventana (igual en macOS, Windows y Linux):
/// se restaura, se pone por encima de todo y muestra la pantalla de llamada
/// entrante. La notificación del sistema es un complemento. El timbre suena
/// siempre, aunque el sistema esté en "No molestar".
class NotificationManager extends ChangeNotifier {
  NotificationManager(this._engine, this._storage);
  final SipEngine _engine;
  final AppStorage _storage;
  static const _channel = MethodChannel('noryxs/window');
  static const _file = 'notifications.json';

  /// Tarjeta flotante sobre el escritorio cuando la ventana está minimizada o en segundo plano.
  bool floatingCard = true;

  /// Escritorio: abrir NORYXS al iniciar sesión (macOS SMAppService, Windows registro Run, Linux autostart).
  bool launchAtLogin = true;
  bool systemNotification = false;

  /// Atajos globales (⌃⌥A / ⌃⌥H / ⌃⌥M en macOS, Ctrl+Alt+… en Windows).
  bool hotkeys = true;

  /// Acción de un atajo o del botón de los cascos: answer | hangup | mute | headset.
  void Function(String action)? onHotkey;
  bool _mediaActive = false;
  String _mediaTitle = '';

  /// Tono de llamada: 0 trino, 2 clásico, 3 suave.
  int ringTone = 0;
  static Map<int, String> get ringTones => {0: tr('Trino digital'), 2: tr('Clásico'), 3: tr('Carillón suave')};

  bool _ringing = false;
  bool _waitingTone = false;
  final Set<int> _alerted = {};
  final Map<int, String> _lastCard = {};

  /// Datos para la tarjeta flotante nativa.
  Map<String, Object?> _cardArgs(CallSession c, List<CallSession> calls) {
    final active = calls.where((x) => x.callId != c.callId && x.state == CallState.active).firstOrNull;
    final line = describeLine?.call(c) ?? '';
    final ctx = callerContext?.call(c) ?? (geo: '', lastNote: '');
    final initials = c.displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑ]').hasMatch(p[0])).map((p) => p[0]).take(2).join().toUpperCase();
    return {
      'callId': c.callId,
      'lineBadge': line.toUpperCase(),
      'name': c.displayName.isEmpty ? tr('Número oculto') : c.displayName,
      'number': c.displayName != c.remoteNumber ? c.remoteNumber : '',
      'initials': initials,
      'note': active != null
          ? tr('Al contestar se retendrá {0}', [active.displayName])
          : (ctx.lastNote.isNotEmpty ? tr('Última nota: {0}', [ctx.lastNote]) : tr('Destino: {0}', [line])),
      'geo': ctx.geo,
      'lastNote': ctx.lastNote,
      'muted': c.ringSilenced,
      'card': floatingCard,
      'notify': systemNotification,
      'title': tr('Llamada entrante · {0}', [line]),
      'body': c.displayName.isEmpty ? tr('Número oculto') : c.displayName,
    };
  }

  void Function()? onWake;

  /// Clic para llamar: enlace tel:/sip:/callto: abierto con la app.
  void Function(String url)? onOpenUrl;
  void Function(int callId)? onAnswerFromNotification;
  void Function(int callId)? onRejectFromNotification;
  void Function(int callId)? onSilenceFromNotification;
  String Function(CallSession c)? describeLine;

  /// Timbre de la línea de la llamada (-1 = el general).
  int Function(CallSession c)? toneFor;
  int _currentTone = -1;

  /// Origen del número y última nota (para la tarjeta flotante / notificación).
  ({String geo, String lastNote}) Function(CallSession c)? callerContext;

  Future<void> init() async {
    final s = await _storage.read(_file);
    if (s is Map<String, dynamic>) {
      floatingCard = s['floatingCard'] as bool? ?? true;
      hotkeys = s['hotkeys'] as bool? ?? true;
      launchAtLogin = s['launchAtLogin'] as bool? ?? true;
      systemNotification = s['systemNotification'] as bool? ?? false;
      ringTone = (s['ringTone'] as num?)?.toInt() ?? 0;
    }
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'wake':
          onWake?.call();
        case 'hotkey':
          final a = args['action'] as String? ?? '';
          if (a.isNotEmpty) onHotkey?.call(a);
        case 'openUrl':
          final u = args['url'] as String? ?? '';
          if (u.isNotEmpty) onOpenUrl?.call(u);
        case 'notificationAction':
          final id = (args['callId'] as num?)?.toInt() ?? -1;
          if (args['action'] == 'answer') onAnswerFromNotification?.call(id);
          if (args['action'] == 'reject') onRejectFromNotification?.call(id);
          if (args['action'] == 'mute') onSilenceFromNotification?.call(id);
      }
      return null;
    });
    // Enlaces que llegaron antes de que Dart escuchara (p. ej. la app se abrió con un tel:)
    try {
      final pending = await _channel.invokeMethod<List<dynamic>>('urlHandlerReady');
      for (final u in pending ?? const []) {
        if (u is String && u.isNotEmpty) onOpenUrl?.call(u);
      }
    } catch (_) {}
    if (systemNotification || Platform.isIOS) _invoke('requestNotificationPermission');
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) _invoke('setLaunchAtLogin', {'enabled': launchAtLogin});
    if (Platform.isMacOS || Platform.isWindows) _invoke('setHotkeys', {'enabled': hotkeys});
  }

  Future<void> setPrefs({bool? card, bool? notify, int? tone, bool? login, bool? keys}) async {
    if (card != null) floatingCard = card;
    if (keys != null) {
      hotkeys = keys;
      _invoke('setHotkeys', {'enabled': keys});
    }
    if (login != null) {
      launchAtLogin = login;
      _invoke('setLaunchAtLogin', {'enabled': login});
    }
    if (tone != null) {
      ringTone = tone;
      if (_ringing && !_waitingTone) _engine.ringStart(tone: ringTone);
    }
    if (notify != null) {
      systemNotification = notify;
      if (notify) _invoke('requestNotificationPermission');
    }
    notifyListeners();
    await _storage.write(_file, {'floatingCard': floatingCard, 'systemNotification': systemNotification, 'ringTone': ringTone, 'launchAtLogin': launchAtLogin, 'hotkeys': hotkeys});
  }

  /// Selector de ficheros nativo: ruta elegida o null.
  Future<String?> pickFile({String title = ''}) async {
    try {
      return await _channel.invokeMethod<String>('pickFile', {'title': title});
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveFile(String name, {String title = ''}) async {
    try {
      return await _channel.invokeMethod<String>('saveFile', {'name': name, 'title': title});
    } catch (_) {
      return null;
    }
  }

  /// Pide al sistema que NORYXS abra los enlaces tel:/sip:/callto:.
  Future<bool> setDefaultDialer() async {
    try {
      return await _channel.invokeMethod<bool>('setDefaultDialer') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDefaultDialer() async {
    try {
      return await _channel.invokeMethod<bool>('isDefaultDialer') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Escucha el tono seleccionado durante 3 s.
  void previewTone(int tone) {
    if (_ringing) return;
    _engine.ringStart(tone: tone);
    Timer(const Duration(seconds: 3), () {
      if (!_ringing) _engine.ringStop();
    });
  }

  /// Se llama en cada cambio de llamadas.
  void update(List<CallSession> calls) {
    // 0) Botón de los cascos: activo solo mientras hay una llamada sonando o en curso
    final live = calls.where((c) => c.state.isLive).toList();
    final active = live.isNotEmpty;
    final title = active ? live.first.displayName : '';
    if (active != _mediaActive || (active && title != _mediaTitle)) {
      _mediaActive = active;
      _mediaTitle = title;
      _invoke('setMediaSession', {'active': active, 'title': title.isEmpty ? tr('Llamada') : title});
    }
    // 1) Avisar de llamadas entrantes nuevas
    for (final c in calls) {
      if (c.state == CallState.incoming && !_alerted.contains(c.callId)) {
        _alerted.add(c.callId);
        _invoke('incomingCall', _cardArgs(c, calls));
      }
    }
    // 1b) Actualizar la tarjeta (tono silenciado, otra llamada activa…)
    for (final c in calls) {
      if (c.state == CallState.incoming && _alerted.contains(c.callId)) {
        final args = _cardArgs(c, calls);
        final key = args.toString();
        if (_lastCard[c.callId] != key) {
          _lastCard[c.callId] = key;
          _invoke('updateCall', args);
        }
      }
    }
    // 2) Las que dejaron de sonar (contestadas, rechazadas o perdidas)
    for (final id in _alerted.toList()) {
      final c = calls.where((x) => x.callId == id).firstOrNull;
      if (c == null || c.state != CallState.incoming) {
        _alerted.remove(id);
        _lastCard.remove(id);
        _invoke('callHandled', {'callId': id, 'answered': c != null && (c.wasAnswered || c.state == CallState.connecting || c.state == CallState.active)});
      }
    }

    // 3) Timbre: normal, o aviso suave si ya hay otra conversación
    final ringingCalls = calls.where((c) => c.state == CallState.incoming && !c.ringSilenced);
    final busy = calls.any((c) => c.state == CallState.active || c.state == CallState.held);
    final shouldRing = ringingCalls.isNotEmpty;
    final lineTone = shouldRing ? (toneFor?.call(ringingCalls.first) ?? -1) : -1;
    final tone = lineTone >= 0 ? lineTone : ringTone;
    if (shouldRing && (!_ringing || _waitingTone != busy || _currentTone != tone)) {
      _engine.ringStart(waiting: busy, tone: tone);
      _waitingTone = busy;
      _currentTone = tone;
      _ringing = true;
    } else if (!shouldRing && _ringing) {
      _engine.ringStop();
      _ringing = false;
    }
  }

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // Plataforma sin implementación nativa todavía (Windows/Linux): se ignora.
    }
  }
}

import '../engine/sip_engine.dart';
import 'i18n.dart';

// ---------------------------------------------------------------------------
// Cuenta SIP (configuración persistente; la contraseña vive en el Llavero)
// ---------------------------------------------------------------------------

class SipAccountConfig {
  SipAccountConfig({
    required this.id,
    this.name = '',
    this.username = '',
    this.authUser = '',
    this.server = '',
    this.port = 5060,
    this.transport = SipTransport.udp,
    this.domain = '',
    this.proxy = '',
    this.expires = 300,
    this.srtp = 0,
    this.enabled = true,
    this.ringTone = -1,
    List<String>? queues,
  }) : queues = queues ?? [];

  final String id;
  String name;
  String username;
  String authUser;
  String server;
  int port;
  SipTransport transport;
  String domain;
  String proxy;
  int expires;
  int srtp; // 0 desactivado, 1 opcional, 2 obligatorio
  bool enabled;

  /// Timbre propio de la línea (0 trino, 2 clásico, 3 suave); -1 = el general.
  int ringTone;

  /// Colas de FreePBX que atiende esta línea (panel "En espera": Atender la pasa a esta extensión).
  List<String> queues;

  String get secretKey => 'sip_password_$id';
  bool get isComplete => username.isNotEmpty && server.isNotEmpty;
  String get transportLabel => transport.name.toUpperCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'authUser': authUser,
        'server': server,
        'port': port,
        'transport': transport.name,
        'domain': domain,
        'proxy': proxy,
        'expires': expires,
        'srtp': srtp,
        'enabled': enabled,
        'ringTone': ringTone,
        if (queues.isNotEmpty) 'queues': queues,
      };

  factory SipAccountConfig.fromJson(Map<String, dynamic> j) => SipAccountConfig(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        username: j['username'] as String? ?? '',
        authUser: j['authUser'] as String? ?? '',
        server: j['server'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 5060,
        transport: SipTransport.values.firstWhere((t) => t.name == j['transport'], orElse: () => SipTransport.udp),
        domain: j['domain'] as String? ?? '',
        proxy: j['proxy'] as String? ?? '',
        expires: (j['expires'] as num?)?.toInt() ?? 300,
        srtp: (j['srtp'] as num?)?.toInt() ?? 0,
        enabled: j['enabled'] as bool? ?? true,
        ringTone: (j['ringTone'] as num?)?.toInt() ?? -1,
        queues: (j['queues'] as List?)?.map((e) => e.toString()).toList(),
      );
}

enum RegState { unregistered, registering, registered, authError, connectionError, error }

extension RegStateText on RegState {
  String get label => switch (this) {
        RegState.unregistered => tr('No registrada'),
        RegState.registering => tr('Registrando…'),
        RegState.registered => tr('Registrada'),
        RegState.authError => tr('Error de autenticación'),
        RegState.connectionError => tr('Error de conexión'),
        RegState.error => tr('Error'),
      };
}

// ---------------------------------------------------------------------------
// Línea: hueco del terminal asociado a una cuenta SIP
// ---------------------------------------------------------------------------

enum LineStatus { free, ringing, busy, held, disconnected }

extension LineStatusText on LineStatus {
  String get label => switch (this) {
        LineStatus.free => tr('Libre'),
        LineStatus.ringing => tr('Sonando'),
        LineStatus.busy => tr('Ocupada'),
        LineStatus.held => tr('Retenida'),
        LineStatus.disconnected => tr('Desconectada'),
      };
}

class SipLine {
  SipLine({required this.index, required this.account});
  int index; // 0-based
  SipAccountConfig account;
  int accId = -1; // id en el motor
  RegState reg = RegState.unregistered;
  int regCode = 0;
  String regReason = '';

  int get number => index + 1;
  String get label => tr('LÍNEA {0}', [number]);
  String get extension => account.username.isEmpty ? '—' : account.username;
}

// ---------------------------------------------------------------------------
// Sesión de llamada
// ---------------------------------------------------------------------------

enum CallState { incoming, outgoing, ringing, connecting, active, held, transferring, ended, failed }

extension CallStateText on CallState {
  String get label => switch (this) {
        CallState.incoming => tr('Entrante'),
        CallState.outgoing => tr('Llamando…'),
        CallState.ringing => tr('Sonando'),
        CallState.connecting => tr('Conectando…'),
        CallState.active => tr('En conversación'),
        CallState.held => tr('Retenida'),
        CallState.transferring => tr('Transfiriendo…'),
        CallState.ended => tr('Finalizada'),
        CallState.failed => tr('Fallida'),
      };
  bool get isLive => this != CallState.ended && this != CallState.failed;
}

class CallSession {
  CallSession({required this.callId, required this.accId, required this.incoming, required this.remoteNumber});

  final int callId;
  final int accId;
  final bool incoming;
  final DateTime createdAt = DateTime.now();
  String remoteNumber;
  String remoteName = '';
  String contactName = '';
  CallState state = CallState.outgoing;
  DateTime? connectedAt;
  DateTime? endedAt;
  bool remoteHold = false;
  bool ringSilenced = false;
  int statusCode = 0;
  String statusText = '';

  /// Nota rápida y etiquetas escritas durante la llamada (pasan al historial al colgar).
  String note = '';

  /// Ficheros WAV grabados durante esta llamada.
  final List<String> recordings = [];
  List<String> tags = [];

  /// Llamada de servicio a un código de FreePBX (*72, *78…): oculta, sin historial.
  bool service = false;

  /// Si esta llamada es la consulta de una transferencia atendida,
  /// id de la llamada original que queda retenida.
  int? consultFor;

  bool get wasAnswered => connectedAt != null;
  String get displayName => contactName.isNotEmpty ? contactName : (remoteName.isNotEmpty ? remoteName : remoteNumber);

  Duration get duration {
    if (connectedAt == null) return Duration.zero;
    return (endedAt ?? DateTime.now()).difference(connectedAt!);
  }
}

// ---------------------------------------------------------------------------
// Agenda e historial
// ---------------------------------------------------------------------------

class Contact {
  Contact({required this.id, required this.name, required this.number, this.company = '', this.favorite = false});
  final String id;
  String name;
  String number;
  String company;
  bool favorite;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'number': number, 'company': company, 'favorite': favorite};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        number: j['number'] as String? ?? '',
        company: j['company'] as String? ?? '',
        favorite: j['favorite'] as bool? ?? false,
      );
}

enum HistoryType { incoming, outgoing, missed }

class HistoryEntry {
  HistoryEntry({
    String? id,
    required this.type,
    required this.number,
    required this.name,
    required this.lineNumber,
    required this.extension,
    required this.start,
    required this.durationSec,
    this.note = '',
    List<String>? tags,
    List<String>? recordings,
  })  : id = id ?? '${start.microsecondsSinceEpoch.toRadixString(36)}-${number.hashCode.toUnsigned(20).toRadixString(36)}',
        tags = tags ?? [],
        recordings = recordings ?? [];

  /// Identificador único del registro (une la llamada con su nota y etiquetas).
  final String id;
  final HistoryType type;
  final String number;
  final String name;
  final int lineNumber;
  final String extension;
  final DateTime start;
  final int durationSec;

  /// Nota rápida y etiquetas: se guardan cifradas aparte (notes.json), nunca en history.json.
  String note;
  List<String> tags;

  /// Grabaciones de la llamada (rutas a los WAV).
  final List<String> recordings;

  bool get hasContext => note.trim().isNotEmpty || tags.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'number': number,
        'name': name,
        'line': lineNumber,
        'ext': extension,
        'start': start.toIso8601String(),
        'duration': durationSec,
        if (recordings.isNotEmpty) 'rec': recordings,
      };
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String?,
        type: HistoryType.values.firstWhere((t) => t.name == j['type'], orElse: () => HistoryType.outgoing),
        number: j['number'] as String? ?? '',
        name: j['name'] as String? ?? '',
        lineNumber: (j['line'] as num?)?.toInt() ?? 1,
        extension: j['ext'] as String? ?? '',
        start: DateTime.tryParse(j['start'] as String? ?? '') ?? DateTime.now(),
        durationSec: (j['duration'] as num?)?.toInt() ?? 0,
        recordings: (j['rec'] as List?)?.whereType<String>().toList(),
      );
}

/// Etiqueta de contexto (el id y el color son fijos; el nombre se puede cambiar).
class CallTag {
  CallTag({required this.id, required this.label, required this.color});
  final String id; // t1..t4
  String label;
  final String color; // gold, red, sky, green
}

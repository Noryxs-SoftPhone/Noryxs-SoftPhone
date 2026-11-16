// Cola de llamadas en FreePBX vista desde el terminal (Asterisk Manager Interface).
//
// El usuario AMI es limitado (read=call,agent / write=call): solo puede ver la
// cola y mover o colgar llamadas en espera. La contraseña vive en el Llavero.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';
import 'storage.dart';

class QueueCaller {
  QueueCaller({required this.channel, required this.queue, required this.number, required this.name, required this.joinedAt, required this.position});
  final String channel;
  String queue;
  String number;
  String name;
  DateTime joinedAt;
  int position;
  bool pickupRequested = false;

  String get display => name.isNotEmpty && name != '<unknown>' && name != number ? name : (number.isEmpty ? 'Número oculto' : number);
  Duration get waiting => DateTime.now().difference(joinedAt);
}

enum AmiState { disabled, connecting, connected, authError, error }

class QueueConfig {
  bool enabled = false;
  String host = '';
  int port = 5038;
  String user = 'noryxs';
  List<String> queues = ['400'];

  Map<String, dynamic> toJson() => {'enabled': enabled, 'host': host, 'port': port, 'user': user, 'queues': queues};
  void fromJson(Map<String, dynamic> j) {
    enabled = j['enabled'] as bool? ?? false;
    host = j['host'] as String? ?? '';
    port = (j['port'] as num?)?.toInt() ?? 5038;
    user = j['user'] as String? ?? 'noryxs';
    queues = (j['queues'] as List?)?.map((e) => e.toString()).toList() ?? ['400'];
  }
}

class QueueManager extends ChangeNotifier {
  QueueManager(this._engine, this._storage);
  final SipEngine _engine;
  final AppStorage _storage;
  static const _file = 'queue.json';
  static const _secretKey = 'ami_password';

  final QueueConfig config = QueueConfig();
  final Map<String, QueueCaller> _callers = {}; // por canal
  AmiState state = AmiState.disabled;
  String stateText = '';

  Socket? _sock;
  final _buf = StringBuffer();
  Timer? _reconnect;
  Timer? _keepalive;
  int _actionSeq = 0;
  bool _disposed = false;

  List<QueueCaller> get callers => _callers.values.toList()..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
  bool get hasPassword => (_engine.secretGet(_secretKey) ?? '').isNotEmpty;

  /// Pendiente de autocontestar: número que acabamos de pedir a la cola.
  String? pendingPickupNumber;
  DateTime? _pendingAt;

  Future<void> load() async {
    final d = await _storage.read(_file);
    if (d is Map<String, dynamic>) config.fromJson(d);
    if (config.enabled) connect();
  }

  Future<void> save({String? password}) async {
    if (password != null && password.isNotEmpty) _engine.secretSet(_secretKey, password);
    await _storage.write(_file, config.toJson());
    disconnect();
    if (config.enabled) connect();
    notifyListeners();
  }

  // ---------------- Conexión ----------------

  Future<void> connect() async {
    _reconnect?.cancel();
    if (!config.enabled || config.host.isEmpty) {
      _setState(AmiState.disabled, 'Desactivado');
      return;
    }
    final pwd = _engine.secretGet(_secretKey) ?? '';
    if (pwd.isEmpty) {
      _setState(AmiState.authError, 'Falta la contraseña AMI');
      return;
    }
    _setState(AmiState.connecting, 'Conectando con ${config.host}…');
    try {
      final s = await Socket.connect(config.host, config.port, timeout: const Duration(seconds: 6));
      _sock = s;
      s.setOption(SocketOption.tcpNoDelay, true);
      s.cast<List<int>>().transform(utf8.decoder).listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
      _send({'Action': 'Login', 'Username': config.user, 'Secret': pwd, 'Events': 'call,agent'}, id: 'login');
    } catch (e) {
      _setState(AmiState.error, 'Sin conexión AMI (${config.host}:${config.port})');
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _reconnect?.cancel();
    _keepalive?.cancel();
    try {
      _sock?.destroy();
    } catch (_) {}
    _sock = null;
    _callers.clear();
    _setState(config.enabled ? AmiState.connecting : AmiState.disabled, '');
  }

  void _onClosed() {
    _sock = null;
    _keepalive?.cancel();
    if (_disposed) return;
    if (state != AmiState.authError) {
      _setState(AmiState.error, 'Conexión AMI perdida · reintentando');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    if (config.enabled) _reconnect = Timer(const Duration(seconds: 8), connect);
  }

  void _setState(AmiState s, String t) {
    state = s;
    stateText = t;
    notifyListeners();
  }

  void _send(Map<String, String> m, {String? id}) {
    final s = _sock;
    if (s == null) return;
    final aid = id ?? 'nx${_actionSeq++}';
    final b = StringBuffer();
    m.forEach((k, v) => b.write('$k: $v\r\n'));
    b.write('ActionID: $aid\r\n\r\n');
    s.write(b.toString());
  }

  // ---------------- Protocolo ----------------

  void _onData(String chunk) {
    _buf.write(chunk);
    var text = _buf.toString();
    int idx;
    while ((idx = text.indexOf('\r\n\r\n')) >= 0) {
      final block = text.substring(0, idx);
      text = text.substring(idx + 4);
      final msg = <String, String>{};
      for (final line in block.split('\r\n')) {
        final c = line.indexOf(':');
        if (c > 0) msg[line.substring(0, c).trim()] = line.substring(c + 1).trim();
      }
      if (msg.isNotEmpty) _onMessage(msg);
    }
    _buf
      ..clear()
      ..write(text);
  }

  void _onMessage(Map<String, String> m) {
    if (m['ActionID'] == 'login') {
      if (m['Response'] == 'Success') {
        _setState(AmiState.connected, 'Conectado · ${config.queues.map((q) => 'cola $q').join(', ')}');
        _snapshot();
        _keepalive = Timer.periodic(const Duration(seconds: 25), (_) {
          _send({'Action': 'Ping'});
          _snapshot(); // corrige posibles desfases
        });
      } else {
        _setState(AmiState.authError, 'Usuario o contraseña AMI incorrectos');
        disconnect();
        state = AmiState.authError;
      }
      return;
    }
    final ev = m['Event'];
    if (ev == null) return;
    final q = m['Queue'] ?? '';
    if (q.isNotEmpty && !config.queues.contains(q)) return;
    switch (ev) {
      case 'QueueEntry': // respuesta a QueueStatus
        final ch = m['Channel'] ?? '';
        final wait = int.tryParse(m['Wait'] ?? '0') ?? 0;
        _snapshotSeen.add(ch);
        final c = _callers[ch];
        if (c == null) {
          _callers[ch] = QueueCaller(
            channel: ch,
            queue: q,
            number: m['CallerIDNum'] ?? '',
            name: m['CallerIDName'] ?? '',
            joinedAt: DateTime.now().subtract(Duration(seconds: wait)),
            position: int.tryParse(m['Position'] ?? '0') ?? 0,
          );
        } else {
          c.position = int.tryParse(m['Position'] ?? '0') ?? c.position;
        }
        notifyListeners();
      case 'QueueStatusComplete':
        _callers.removeWhere((ch, _) => !_snapshotSeen.contains(ch));
        _snapshotSeen.clear();
        notifyListeners();
      case 'QueueCallerJoin':
        final ch = m['Channel'] ?? '';
        _callers[ch] = QueueCaller(
          channel: ch,
          queue: q,
          number: m['CallerIDNum'] ?? '',
          name: m['CallerIDName'] ?? '',
          joinedAt: DateTime.now(),
          position: int.tryParse(m['Position'] ?? '0') ?? 0,
        );
        notifyListeners();
      case 'QueueCallerLeave' || 'QueueCallerAbandon':
        _callers.remove(m['Channel'] ?? '');
        _renumber();
        notifyListeners();
      case 'Hangup':
        if (_callers.remove(m['Channel'] ?? '') != null) {
          _renumber();
          notifyListeners();
        }
    }
  }

  final Set<String> _snapshotSeen = {};

  void _snapshot() {
    _snapshotSeen.clear();
    for (final q in config.queues) {
      _send({'Action': 'QueueStatus', 'Queue': q});
    }
  }

  void _renumber() {
    var i = 1;
    for (final c in callers) {
      c.position = i++;
    }
  }

  // ---------------- Acciones ----------------

  /// Atender: la llamada en espera se envía a nuestra extensión y el
  /// terminal la contesta automáticamente (reteniendo la conversación actual).
  void pickup(QueueCaller c, String myExtension) {
    c.pickupRequested = true;
    pendingPickupNumber = c.number;
    _pendingAt = DateTime.now();
    _redirect(c, 'from-internal', myExtension);
    notifyListeners();
  }

  bool consumePendingPickup(String number) {
    final p = pendingPickupNumber;
    if (p == null || _pendingAt == null) return false;
    if (DateTime.now().difference(_pendingAt!).inSeconds > 15) {
      pendingPickupNumber = null;
      return false;
    }
    final match = p.isEmpty || number.endsWith(p) || p.endsWith(number);
    if (match) pendingPickupNumber = null;
    return match;
  }

  void transfer(QueueCaller c, String extension) => _redirect(c, 'from-internal', extension);

  void toVoicemail(QueueCaller c, String extension) => _redirect(c, 'ext-local', 'vmu$extension');

  void hangup(QueueCaller c) => _send({'Action': 'Hangup', 'Channel': c.channel});

  void _redirect(QueueCaller c, String context, String exten) =>
      _send({'Action': 'Redirect', 'Channel': c.channel, 'Context': context, 'Exten': exten, 'Priority': '1'});

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}

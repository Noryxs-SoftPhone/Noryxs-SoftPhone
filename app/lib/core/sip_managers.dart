// Cuentas SIP, registro y líneas del terminal.
import 'dart:math';
import 'i18n.dart';

import 'package:flutter/foundation.dart';

import '../engine/sip_engine.dart';
import 'models.dart';
import 'storage.dart';

String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// Configuración persistente de cuentas. Las contraseñas van al Llavero.
class SipAccountManager extends ChangeNotifier {
  SipAccountManager(this._storage, this._engine);
  final AppStorage _storage;
  final SipEngine _engine;
  static const _file = 'accounts.json';
  static const minLines = 2; // mínimo garantizado
  static const maxLines = 8; // arquitectura preparada para 8 líneas

  final List<SipAccountConfig> accounts = [];

  Future<void> load() async {
    final data = await _storage.read(_file);
    accounts.clear();
    if (data is List) {
      accounts.addAll(data.cast<Map<String, dynamic>>().map(SipAccountConfig.fromJson));
    }
    while (accounts.length < minLines) {
      accounts.add(SipAccountConfig(id: newId(), name: tr('Línea {0}', [accounts.length + 1])));
    }
    notifyListeners();
  }

  Future<void> save() async {
    await _storage.write(_file, accounts.map((a) => a.toJson()).toList());
    notifyListeners();
  }

  String? password(SipAccountConfig a) => _engine.secretGet(a.secretKey);
  bool hasPassword(SipAccountConfig a) => (password(a) ?? '').isNotEmpty;

  /// Devuelve false si la contraseña no se pudo guardar en el almacén seguro.
  Future<bool> update(SipAccountConfig a, {String? newPassword}) async {
    var ok = true;
    if (newPassword != null && newPassword.isNotEmpty) {
      ok = _engine.secretSet(a.secretKey, newPassword);
    }
    await save();
    return ok;
  }

  Future<SipAccountConfig?> addLine() async {
    if (accounts.length >= maxLines) return null;
    final a = SipAccountConfig(id: newId(), name: tr('Línea {0}', [accounts.length + 1]));
    accounts.add(a);
    await save();
    return a;
  }

  Future<void> removeLine(SipAccountConfig a) async {
    if (accounts.length <= minLines) return;
    accounts.remove(a);
    _engine.secretDelete(a.secretKey);
    await save();
  }
}

/// Líneas del terminal (una por cuenta) y línea de salida seleccionada.
class MultiLineManager extends ChangeNotifier {
  final List<SipLine> lines = [];
  int selected = 0;

  void sync(List<SipAccountConfig> accounts) {
    final old = {for (final l in lines) l.account.id: l};
    lines
      ..clear()
      ..addAll([
        for (var i = 0; i < accounts.length; i++)
          (old[accounts[i].id]?..account = accounts[i]) ?? SipLine(index: i, account: accounts[i])
      ]);
    for (var i = 0; i < lines.length; i++) {
      lines[i].index = i;
    }
    if (selected >= lines.length) selected = 0;
    notifyListeners();
  }

  SipLine? byAcc(int accId) {
    for (final l in lines) {
      if (l.accId == accId && accId >= 0) return l;
    }
    return null;
  }

  SipLine get selectedLine => lines[selected];

  void select(int i) {
    if (i < 0 || i >= lines.length) return;
    selected = i;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// Alta de cuentas en el motor y seguimiento del estado de registro.
class SipRegistrationManager {
  SipRegistrationManager(this._engine, this._accounts, this._lines);
  final SipEngine _engine;
  final SipAccountManager _accounts;
  final MultiLineManager _lines;

  /// (Re)crea la cuenta de una línea en PJSIP y lanza el registro.
  void apply(SipLine line) {
    if (line.accId >= 0) {
      _engine.removeAccount(line.accId);
      line.accId = -1;
    }
    final a = line.account;
    final pwd = _accounts.password(a);
    if (!a.enabled || !a.isComplete) {
      line.reg = RegState.unregistered;
      line.regCode = 0;
      line.regReason = a.isComplete ? tr('Desactivada') : tr('Sin configurar');
      _lines.changed();
      return;
    }
    if (pwd == null || pwd.isEmpty) {
      line.reg = RegState.unregistered;
      line.regReason = tr('Falta la contraseña');
      _lines.changed();
      return;
    }
    final id = _engine.addAccount(AccountParams(
      displayName: a.name,
      username: a.username,
      authUser: a.authUser.isEmpty ? null : a.authUser,
      password: pwd,
      server: a.server,
      port: a.port,
      transport: a.transport,
      domain: a.domain.isEmpty ? null : a.domain,
      proxy: a.proxy.isEmpty ? null : a.proxy,
      expires: a.expires,
      srtp: a.srtp,
    ));
    line.accId = id;
    if (id < 0) {
      line.reg = RegState.error;
      line.regReason = tr('Configuración no válida ({0})', [id]);
    } else {
      line.reg = RegState.registering;
      line.regReason = '';
    }
    _lines.changed();
  }

  void applyAll() {
    for (final l in _lines.lines) {
      apply(l);
    }
  }

  void onEvent(EngineEvent e) {
    if (e.type != 'reg') return;
    final line = _lines.byAcc(e.accId);
    if (line == null) return; // cuenta ya eliminada
    line.reg = switch (e.str('state')) {
      'registering' => RegState.registering,
      'registered' => RegState.registered,
      'unregistering' || 'unregistered' => RegState.unregistered,
      'auth_error' => RegState.authError,
      'connection_error' => RegState.connectionError,
      _ => RegState.error,
    };
    line.regCode = e.intv('code');
    line.regReason = e.str('reason');
    _lines.changed();
  }

  /// Tras suspensión o cambio de red: PJSIP rehace transportes y registros.
  void networkChanged() => _engine.networkChanged();
}

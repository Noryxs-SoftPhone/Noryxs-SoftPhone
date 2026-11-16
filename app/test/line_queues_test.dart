import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/models.dart';

void main() {
  test('colas por línea: se guardan y se leen', () {
    final a = SipAccountConfig(id: 'a1', username: '201', queues: ['400', '401']);
    final b = SipAccountConfig.fromJson(a.toJson());
    expect(b.queues, ['400', '401']);
  });

  test('cuentas antiguas sin colas: lista vacía', () {
    final b = SipAccountConfig.fromJson({'id': 'x', 'username': '202'});
    expect(b.queues, isEmpty);
    expect(b.toJson().containsKey('queues'), isFalse);
  });
}

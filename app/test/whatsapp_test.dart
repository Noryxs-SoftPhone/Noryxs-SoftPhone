import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/whatsapp.dart';

void main() {
  test('números para wa.me', () {
    expect(WhatsAppManager.waNumber('612 84 93 10'), '34612849310');
    expect(WhatsAppManager.waNumber('+44 7700 900123'), '447700900123');
    expect(WhatsAppManager.waNumber('0034612849310'), '34612849310');
    expect(WhatsAppManager.waNumber('201'), isNull); // extensión interna
    expect(WhatsAppManager.waNumber(''), isNull);
  });
  test('plantilla con nombre', () {
    expect(WhatsAppManager.fill('Hola {nombre}', 'Ana'), 'Hola Ana');
  });
}

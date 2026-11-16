import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/provisioning.dart';

void main() {
  const sealed = 'SSP1:abc+/def==';
  test('enlace ida y vuelta', () {
    expect(Provisioning.extract(Provisioning.link(sealed)), sealed);
  });
  test('desde el contenido de un fichero o un texto pegado', () {
    expect(Provisioning.extract('NORYXS · configuración\n$sealed\n'), sealed);
    expect(Provisioning.extract('  $sealed  '), sealed);
  });
  test('sin paquete', () {
    expect(Provisioning.extract('hola'), isNull);
    expect(Provisioning.extract('noryxs:provision'), isNull);
  });
}

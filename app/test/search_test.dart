import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/search.dart';

void main() {
  test('sin acentos ni mayúsculas', () {
    expect(matchesQuery('garcia', texts: ['Sr. García']), isTrue);
    expect(matchesQuery('RECEPCIÓN', texts: ['recepcion']), isTrue);
    expect(matchesQuery('lopez', texts: ['García']), isFalse);
  });
  test('números por dígitos', () {
    expect(matchesQuery('612 84', numbers: ['+34612849310']), isTrue);
    expect(matchesQuery('+34 612849', numbers: ['612849310']), isTrue);
    expect(matchesQuery('201', numbers: ['201']), isTrue);
    expect(matchesQuery('999', numbers: ['612849310']), isFalse);
  });
  test('vacío encuentra todo', () {
    expect(matchesQuery('  ', texts: ['x']), isTrue);
  });
}

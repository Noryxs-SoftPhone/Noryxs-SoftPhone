import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/phone_info.dart';

void main() {
  String l(String n) => PhoneNumbers.lookup(n)?.display ?? '-';

  test('formato canónico', () {
    expect(PhoneNumbers.canonical('+34 612 849 310'), '+34612849310');
    expect(PhoneNumbers.canonical('0034612849310'), '+34612849310');
    expect(PhoneNumbers.canonical('612849310'), '+34612849310');
    expect(PhoneNumbers.canonical('34612849310'), '+34612849310');
    expect(PhoneNumbers.canonical('201'), '201');
    expect(PhoneNumbers.canonical('*97'), '*97');
    expect(PhoneNumbers.same('612 849 310', '+34612849310'), isTrue);
    expect(PhoneNumbers.same('201', '202'), isFalse);
  });

  test('origen', () {
    expect(l('+34 934 118 209'), '🇪🇸 Barcelona • Fijo');
    expect(l('915551234'), '🇪🇸 Madrid • Fijo');
    expect(l('954000000'), '🇪🇸 Sevilla • Fijo');
    expect(l('822000000'), '🇪🇸 Santa Cruz de Tenerife • Fijo');
    expect(l('612849310'), '🇪🇸 Móvil nacional');
    expect(l('900123123'), '🇪🇸 Número gratuito');
    expect(l('+33 6 12 34 56 78'), '🇫🇷 Francia • Móvil');
    expect(l('+33 1 44 55 66 77'), '🇫🇷 Francia • Fijo');
    expect(l('+351 912 345 678'), '🇵🇹 Portugal • Móvil');
    expect(l('+1 809 555 1234'), '🇩🇴 República Dominicana');
    expect(l('+44 7700 900123'), '🇬🇧 Reino Unido • Móvil');
    expect(l('201'), 'Extensión interna');
    expect(PhoneNumbers.lookup('*97'), isNull);
  });
}

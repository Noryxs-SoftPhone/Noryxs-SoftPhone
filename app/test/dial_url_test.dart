import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/dial_url.dart';

void main() {
  test('tel', () {
    expect(parseDialUrl('tel:+34 600 11 22 33'), '+34600112233');
    expect(parseDialUrl('tel:600-112-233'), '600112233');
    expect(parseDialUrl('TEL:%2B34600112233'), '+34600112233');
    expect(parseDialUrl('tel:201;phone-context=hotel'), '201');
  });
  test('sip y callto', () {
    expect(parseDialUrl('sip:201@pbx.hotel.es'), '201');
    expect(parseDialUrl('sips:+34600112233@pbx;transport=tls'), '+34600112233');
    expect(parseDialUrl('callto://600112233'), '600112233');
  });
  test('no marcables', () {
    expect(parseDialUrl('https://example.com'), isNull);
    expect(parseDialUrl('sip:recepcion@pbx'), isNull);
    expect(parseDialUrl('tel:'), isNull);
  });
}

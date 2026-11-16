import 'package:flutter_test/flutter_test.dart';
import 'package:noryxs_terminal/core/updates.dart';

void main() {
  test('comparación de versiones', () {
    expect(UpdateManager.isNewer('1.0.1', '1.0.0'), isTrue);
    expect(UpdateManager.isNewer('1.2.10', '1.2.9'), isTrue);
    expect(UpdateManager.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(UpdateManager.isNewer('0.9.9', '1.0.0'), isFalse);
    expect(UpdateManager.isNewer('2.0', '1.9.9'), isTrue);
  });
}

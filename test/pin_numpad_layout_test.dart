import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/pin_numpad_layout.dart';

void main() {
  test('keeps the PIN keypad compact on wide and narrow screens', () {
    expect(pinNumpadButtonSize(1200), 64);
    expect(pinNumpadButtonSize(180), 48);
  });
}

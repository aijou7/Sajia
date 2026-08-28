import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/features/owner_web/owner_web_app.dart';

void main() {
  test('owner dashboard password requires eight characters and a digit', () {
    expect(isValidOwnerDashboardPassword('Sajia123'), isTrue);
    expect(isValidOwnerDashboardPassword('abcdefgh'), isFalse);
    expect(isValidOwnerDashboardPassword('Sajia12'), isFalse);
    expect(isValidOwnerDashboardPassword('SajiaPassword'), isFalse);
  });
}

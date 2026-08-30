import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/legacy_outlet.dart';

void main() {
  test('recognizes only the exact legacy setup placeholder', () {
    expect(
      isLegacyPlaceholderOutlet(
        id: legacyPlaceholderOutletId,
        name: '  nama kafe saya ',
      ),
      isTrue,
    );
    expect(
      isLegacyPlaceholderOutlet(
        id: legacyPlaceholderOutletId,
        name: 'Kafe Saya Yang Sebenarnya',
      ),
      isFalse,
    );
    expect(
      isLegacyPlaceholderOutlet(id: 'outlet-123', name: 'Nama Kafe Saya'),
      isFalse,
    );
  });
}

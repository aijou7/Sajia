import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/domain/ingredient_inventory.dart';

void main() {
  final purchase = <String, dynamic>{
    'id': 'milk-buy',
    'occurred_at': '2026-10-01',
    'total': 22000,
    'items': [
      {
        'ingredient_id': 'milk',
        'quantity': '3',
        'unit': 'liter',
        'price': 22000
      }
    ],
  };
  test('price corrections use highest revision, not response order or date',
      () {
    final rows = applyPurchasePriceCorrections([
      purchase
    ], [
      {
        'purchase_id': 'milk-buy',
        'revision': 2,
        'total': 66000,
        'created_at': '2026-10-09',
        'corrected_items': [
          {
            'ingredient_id': 'milk',
            'quantity': '3',
            'unit': 'liter',
            'price': 66000
          }
        ]
      },
      {
        'purchase_id': 'milk-buy',
        'revision': 1,
        'total': 44000,
        'created_at': '2026-10-10',
        'corrected_items': []
      },
    ]);
    expect(rows.single['total'], 66000);
    expect(rows.single['original_total'], 22000);
    expect(rows.single['correction_revision'], 2);
    expect(rows.single['occurred_at'], '2026-10-01');
    expect((rows.single['items'] as List).single['quantity'], '3');
    expect(purchase['total'], 22000);
    expect((purchase['items'] as List).single['price'], 22000);
    expect(purchase.containsKey('correction_revision'), false);
  });
  test('uncorrected receipts remain available with revision zero', () {
    expect(applyPurchasePriceCorrections([purchase], []).single,
        {...purchase, 'original_total': 22000, 'correction_revision': 0});
  });
  test('invalid audit rows do not silently revert a corrected report', () {
    expect(
        () => applyPurchasePriceCorrections([
              purchase
            ], [
              {'purchase_id': 'milk-buy', 'revision': 0, 'corrected_items': []}
            ]),
        throwsFormatException);
  });
}

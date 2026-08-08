import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/domain/product_variant_options.dart';

void main() {
  group('product variant options', () {
    test('parses JSON and removes empty or duplicate options', () {
      expect(
        parseProductVariantOptions(
          '["Regular", "Large", "regular", "  "]',
        ),
        ['Regular', 'Large'],
      );
    });

    test('keeps compatibility with comma and newline separated values', () {
      expect(
        parseProductVariantOptions('Normal, Less\nNo Sugar'),
        ['Normal', 'Less', 'No Sugar'],
      );
    });

    test('encodes a normalized JSON list', () {
      expect(
        encodeProductVariantOptions([' Hot ', 'Cold, 12 oz', 'hot']),
        '["Hot","Cold, 12 oz"]',
      );
    });

    test('parses mixed legacy strings and priced option objects', () {
      final options = parseProductVariantOptionDetails(
        '["Regular", {"name":"Large","price_delta":5000}, '
        '{"label":"Extra Cheese","priceDelta":"8000"}]',
      );

      expect(options.map((option) => option.name), [
        'Regular',
        'Large',
        'Extra Cheese',
      ]);
      expect(options.map((option) => option.priceDelta), [0, 5000, 8000]);
    });

    test('encodes price delta without changing the database column format', () {
      expect(
        encodeProductVariantOptionDetails(const [
          ProductVariantOption(name: 'Regular'),
          ProductVariantOption(name: 'Large', priceDelta: 5000),
        ]),
        '["Regular",{"name":"Large","price_delta":5000}]',
      );
    });

    test('sums only finite positive price deltas', () {
      expect(
        totalVariantPriceDelta(const [
          ProductVariantOption(name: 'Large', priceDelta: 5000),
          ProductVariantOption(name: 'Cheese', priceDelta: 8000),
          ProductVariantOption(name: 'Invalid', priceDelta: -1000),
        ]),
        13000,
      );
    });

    test('builds a stable transaction summary', () {
      expect(
        buildVariantSummary(const [
          MapEntry('Ukuran', 'Large'),
          MapEntry('Level Gula', '50%'),
        ]),
        'Ukuran: Large, Level Gula: 50%',
      );
    });
  });
}

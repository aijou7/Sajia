import 'costing.dart';

class Ingredient {
  const Ingredient(
      {required this.id,
      required this.name,
      required this.unit,
      required this.quantity,
      required this.unitCost,
      this.updatedAt});
  final String id;
  final String name;
  final CostingUnit unit;
  final double quantity;
  final double unitCost;
  final String? updatedAt;

  factory Ingredient.fromJson(Map<String, dynamic> row) => Ingredient(
        id: row['id'].toString(),
        name: row['name'].toString(),
        unit: costingUnitFromStorage(row['unit']?.toString()),
        quantity: double.tryParse(row['quantity'].toString()) ?? 0,
        unitCost: double.tryParse(row['unit_cost'].toString()) ?? 0,
        updatedAt: row['updated_at']?.toString(),
      );
}

/// Original purchase receipts stay immutable so old-client retries still work.
/// Reports display the latest audited price revision, retaining purchase dates
/// and quantities. A correction's creation date is not another purchase date.
List<Map<String, dynamic>> applyPurchasePriceCorrections(
  Iterable<Map<String, dynamic>> purchases,
  Iterable<Map<String, dynamic>> corrections,
) {
  final latest = <String, Map<String, dynamic>>{};
  for (final row in corrections) {
    final revision = int.tryParse(row['revision'].toString());
    if (revision == null || revision <= 0 || row['corrected_items'] is! List) {
      throw const FormatException('Catatan koreksi harga tidak valid.');
    }
    final id = row['purchase_id'].toString();
    if (revision >
        (int.tryParse(latest[id]?['revision'].toString() ?? '') ?? 0)) {
      latest[id] = row;
    }
  }
  return [
    for (final purchase in purchases)
      {
        ...purchase,
        'original_total': purchase['total'],
        'correction_revision': latest[purchase['id']]?['revision'] ?? 0,
        if (latest[purchase['id']] case final correction?) ...{
          'items': correction['corrected_items'],
          'total': correction['total'],
          'price_corrected_at': correction['created_at'],
        },
      },
  ];
}

/// Variants use the same menu recipe, so internal usage groups them by menu.
List<Map<String, dynamic>> aggregateUsageItems(
  Iterable<({String productId, double quantity})> items,
) {
  final quantities = <String, double>{};
  for (final item in items) {
    if (!item.quantity.isFinite || item.quantity <= 0) {
      throw ArgumentError('Jumlah pemakaian tidak valid.');
    }
    quantities.update(item.productId, (q) => q + item.quantity,
        ifAbsent: () => item.quantity);
  }
  return [
    for (final entry in quantities.entries)
      {'product_id': entry.key, 'quantity': entry.value}
  ];
}

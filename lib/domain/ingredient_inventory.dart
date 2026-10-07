import 'costing.dart';

class Ingredient {
  const Ingredient(
      {required this.id,
      required this.name,
      required this.unit,
      required this.quantity,
      required this.unitCost});
  final String id;
  final String name;
  final CostingUnit unit;
  final double quantity;
  final double unitCost;

  factory Ingredient.fromJson(Map<String, dynamic> row) => Ingredient(
        id: row['id'].toString(),
        name: row['name'].toString(),
        unit: costingUnitFromStorage(row['unit']?.toString()),
        quantity: double.tryParse(row['quantity'].toString()) ?? 0,
        unitCost: double.tryParse(row['unit_cost'].toString()) ?? 0,
      );
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

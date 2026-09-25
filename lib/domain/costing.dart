/// Units supported by the per-menu HPP calculator.
///
/// Weight and volume are deliberately kept separate: a gram cannot be
/// converted to a millilitre without a density supplied by the user.
enum CostingUnit {
  gram,
  kilogram,
  milliliter,
  liter,
  piece,
}

extension CostingUnitLabel on CostingUnit {
  String get label => switch (this) {
        CostingUnit.gram => 'gram (g)',
        CostingUnit.kilogram => 'kilogram (kg)',
        CostingUnit.milliliter => 'mililiter (ml)',
        CostingUnit.liter => 'liter (L)',
        CostingUnit.piece => 'pcs',
      };

  String get shortLabel => switch (this) {
        CostingUnit.gram => 'g',
        CostingUnit.kilogram => 'kg',
        CostingUnit.milliliter => 'ml',
        CostingUnit.liter => 'L',
        CostingUnit.piece => 'pcs',
      };

  String get family => switch (this) {
        CostingUnit.gram || CostingUnit.kilogram => 'weight',
        CostingUnit.milliliter || CostingUnit.liter => 'volume',
        CostingUnit.piece => 'piece',
      };

  double get baseFactor => switch (this) {
        CostingUnit.gram => 1,
        CostingUnit.kilogram => 1000,
        CostingUnit.milliliter => 1,
        CostingUnit.liter => 1000,
        CostingUnit.piece => 1,
      };

}

CostingUnit costingUnitFromStorage(String? value) => switch (value) {
      'gram' => CostingUnit.gram,
      'kilogram' => CostingUnit.kilogram,
      'milliliter' => CostingUnit.milliliter,
      'liter' => CostingUnit.liter,
      'piece' => CostingUnit.piece,
      _ => CostingUnit.gram,
    };

class CostingComponent {
  const CostingComponent({
    required this.id,
    required this.outletId,
    required this.productId,
    required this.materialName,
    required this.packageQuantity,
    required this.packageUnit,
    required this.packagePrice,
    required this.recipeQuantity,
    required this.recipeUnit,
    required this.updatedAt,
    this.isSynced = false,
  });

  final String id;
  final String outletId;
  final String productId;
  final String materialName;
  final double packageQuantity;
  final CostingUnit packageUnit;
  final double packagePrice;
  final double recipeQuantity;
  final CostingUnit recipeUnit;
  final DateTime updatedAt;
  final bool isSynced;

  bool get hasCompatibleUnits => packageUnit.family == recipeUnit.family;

  double get packageBaseQuantity => packageQuantity * packageUnit.baseFactor;
  double get recipeBaseQuantity => recipeQuantity * recipeUnit.baseFactor;

  /// Cost of this ingredient used by one portion of the product.
  double get portionCost {
    if (!hasCompatibleUnits ||
        packageQuantity <= 0 ||
        packagePrice < 0 ||
        recipeQuantity < 0 ||
        packageBaseQuantity <= 0) {
      return 0;
    }
    return packagePrice * recipeBaseQuantity / packageBaseQuantity;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'outlet_id': outletId,
        'product_id': productId,
        'material_name': materialName,
        'package_quantity': packageQuantity.toString(),
        'package_unit': packageUnit.name,
        'package_price': packagePrice.toString(),
        'recipe_quantity': recipeQuantity.toString(),
        'recipe_unit': recipeUnit.name,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  CostingComponent copyWith({bool? isSynced}) => CostingComponent(
        id: id,
        outletId: outletId,
        productId: productId,
        materialName: materialName,
        packageQuantity: packageQuantity,
        packageUnit: packageUnit,
        packagePrice: packagePrice,
        recipeQuantity: recipeQuantity,
        recipeUnit: recipeUnit,
        updatedAt: updatedAt,
        isSynced: isSynced ?? this.isSynced,
      );

  static CostingComponent fromJson(Map<String, dynamic> row) => CostingComponent(
        id: row['id']?.toString() ?? '',
        outletId: row['outlet_id']?.toString() ?? '',
        productId: row['product_id']?.toString() ?? '',
        materialName: row['material_name']?.toString() ?? '',
        packageQuantity:
            double.tryParse(row['package_quantity']?.toString() ?? '') ?? 0,
        packageUnit: costingUnitFromStorage(row['package_unit']?.toString()),
        packagePrice:
            double.tryParse(row['package_price']?.toString() ?? '') ?? 0,
        recipeQuantity:
            double.tryParse(row['recipe_quantity']?.toString() ?? '') ?? 0,
        recipeUnit: costingUnitFromStorage(row['recipe_unit']?.toString()),
        updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
            DateTime.now(),
        isSynced: row['is_synced'] == true || row['is_synced'] == 1,
      );
}

double totalCosting(List<CostingComponent> components) => components.fold(
      0,
      (sum, component) => sum + component.portionCost,
    );

/// Rupiah HPP recorded with a transaction after the owner's allowance for
/// calibration, waste, and small ingredients that are difficult to measure.
int bufferedHpp(double baseCogs, int bufferPercent) {
  if (!baseCogs.isFinite || baseCogs < 0 ||
      !const {0, 5, 10}.contains(bufferPercent)) {
    throw ArgumentError('Invalid HPP or buffer percentage');
  }
  return (baseCogs * (100 + bufferPercent) / 100).round();
}

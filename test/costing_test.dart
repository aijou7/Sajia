import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/domain/costing.dart';

CostingComponent _line({
  required double packageQuantity,
  required CostingUnit packageUnit,
  required double packagePrice,
  required double recipeQuantity,
  required CostingUnit recipeUnit,
}) => CostingComponent(
      id: 'line',
      outletId: 'outlet',
      productId: 'product',
      materialName: 'Bahan',
      packageQuantity: packageQuantity,
      packageUnit: packageUnit,
      packagePrice: packagePrice,
      recipeQuantity: recipeQuantity,
      recipeUnit: recipeUnit,
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('mengubah harga kemasan menjadi biaya per takaran resep', () {
    final beans = _line(
      packageQuantity: 1,
      packageUnit: CostingUnit.kilogram,
      packagePrice: 190000,
      recipeQuantity: 18,
      recipeUnit: CostingUnit.gram,
    );

    expect(beans.portionCost, closeTo(3420, 0.001));
  });

  test('menjumlahkan beberapa bahan satu porsi', () {
    final total = totalCosting([
      _line(
        packageQuantity: 1,
        packageUnit: CostingUnit.liter,
        packagePrice: 23000,
        recipeQuantity: 120,
        recipeUnit: CostingUnit.milliliter,
      ),
      _line(
        packageQuantity: 780,
        packageUnit: CostingUnit.milliliter,
        packagePrice: 125000,
        recipeQuantity: 25,
        recipeUnit: CostingUnit.milliliter,
      ),
    ]);

    expect(total, closeTo(6766.4103, 0.001));
  });

  test('menolak konversi beda jenis satuan', () {
    final line = _line(
      packageQuantity: 1,
      packageUnit: CostingUnit.kilogram,
      packagePrice: 190000,
      recipeQuantity: 25,
      recipeUnit: CostingUnit.milliliter,
    );

    expect(line.hasCompatibleUnits, isFalse);
    expect(line.portionCost, 0);
  });
}

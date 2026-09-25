import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/domain/costing.dart';

void main() {
  test('deleting a product removes every recipe component', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'coffee',
        outletId: 'outlet',
        name: 'Kopi Susu',
        price: '20000',
      ),
    );
    final components = ['beans', 'milk'].map((id) => CostingComponent(
          id: id,
          outletId: 'outlet',
          productId: 'coffee',
          materialName: id,
          packageQuantity: 1,
          packageUnit: CostingUnit.kilogram,
          packagePrice: 100000,
          recipeQuantity: 10,
          recipeUnit: CostingUnit.gram,
          updatedAt: DateTime(2026, 9, 26),
        )).toList();
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: components,
    );

    await database.productDao.deleteProduct('coffee');

    expect(await database.costingDao.getForProduct('coffee'), isEmpty);
    expect(await database.productDao.getProduct('coffee'), isNull);
  });
}

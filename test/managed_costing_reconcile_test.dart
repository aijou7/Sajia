import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/domain/costing.dart';

CostingComponent _component(String id, {double price = 100000}) =>
    CostingComponent(
      id: id,
      outletId: 'outlet',
      productId: 'coffee',
      materialName: id,
      packageQuantity: 1,
      packageUnit: CostingUnit.kilogram,
      packagePrice: price,
      recipeQuantity: 10,
      recipeUnit: CostingUnit.gram,
      updatedAt: DateTime(2026, 9, 27),
    );

void main() {
  test('owner-managed status persists locally and is replaced atomically',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.costingDao.replaceManagedProfiles({'coffee': 'outlet'});
    expect(await database.costingDao.isOwnerManagedProduct('coffee'), isTrue);
    await database.costingDao.replaceManagedProfiles({'tea': 'outlet'});
    expect(await database.costingDao.isOwnerManagedProduct('coffee'), isFalse);
    expect(await database.costingDao.isOwnerManagedProduct('tea'), isTrue);

    await database.costingDao.deleteForOutletIds(['outlet']);
    expect(await database.costingDao.isOwnerManagedProduct('tea'), isFalse);
  });

  test('dashboard recipe replaces stale and unsynced local ingredients',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_component('beans'), _component('milk')],
    );

    await database.costingDao.replaceManagedFromRemote(
      'coffee',
      [_component('milk', price: 23000), _component('syrup')],
    );

    final recipe = await database.costingDao.getForProduct('coffee');
    expect(recipe.map((line) => line.id).toSet(), {'milk', 'syrup'});
    expect(recipe.every((line) => line.isSynced), isTrue);
    expect(recipe.firstWhere((line) => line.id == 'milk').packagePrice, 23000);
    expect(await database.costingDao.getUnsynced(), isEmpty);
  });

  test('mismatched remote recipe is rejected without changing local data',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_component('beans')],
    );
    final other = CostingComponent(
      id: 'other',
      outletId: 'outlet',
      productId: 'other-product',
      materialName: 'other',
      packageQuantity: 1,
      packageUnit: CostingUnit.piece,
      packagePrice: 1000,
      recipeQuantity: 1,
      recipeUnit: CostingUnit.piece,
      updatedAt: DateTime(2026, 9, 27),
    );

    await expectLater(
      database.costingDao.replaceManagedFromRemote('coffee', [other]),
      throwsArgumentError,
    );
    expect((await database.costingDao.getForProduct('coffee')).single.id,
        'beans');
  });
}

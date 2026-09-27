import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/features/menu/menu_cost_save.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.outlets).insert(OutletsCompanion.insert(
          id: 'outlet',
          name: 'Cafe',
          licenseKey: 'FREE',
        ));
    await db.productDao.upsertProduct(ProductsCompanion.insert(
      id: 'coffee',
      outletId: 'outlet',
      name: 'Coffee',
      price: '20000',
      cogs: const Value('100'),
    ));
  });

  tearDown(() => db.close());

  test('stale menu form cannot revert dashboard HPP during metadata save',
      () async {
    final opened = (await db.productDao.getProduct('coffee'))!;
    await db.costingDao.markOwnerManagedProduct('coffee', 'outlet');
    await db.productDao.upsertProduct(
      ProductsCompanion(
        id: const Value('coffee'),
        outletId: const Value('outlet'),
        name: const Value('Coffee'),
        price: const Value('20000'),
        cogs: const Value('120'),
      ),
    );

    await db.transaction(() async {
      final resolved = await resolveMenuCostForSave(
        db: db,
        outletId: 'outlet',
        openedProduct: opened,
        recipeEdited: false,
        recipeLines: const [],
        enteredCogs: '100',
      );
      expect(resolved.ownerManaged, isTrue);
      await db.productDao.upsertProduct(ProductsCompanion(
        id: const Value('coffee'),
        outletId: const Value('outlet'),
        name: const Value('Coffee renamed'),
        price: const Value('20000'),
        cogs: Value(resolved.cogs),
      ));
    });

    final checkoutProduct = (await db.productDao.getProduct('coffee'))!;
    expect(checkoutProduct.name, 'Coffee renamed');
    expect(checkoutProduct.cogs, '120');
    // The cashier snapshots product.cogs into a new cart/order item.
    expect(double.tryParse(checkoutProduct.cogs), 120);
  });

  test('a product deleted while its form is open is not recreated', () async {
    final opened = (await db.productDao.getProduct('coffee'))!;
    await db.productDao.deleteProduct('coffee');
    await expectLater(
      db.transaction(() => resolveMenuCostForSave(
            db: db,
            outletId: 'outlet',
            openedProduct: opened,
            recipeEdited: false,
            recipeLines: const [],
            enteredCogs: '100',
          )),
      throwsStateError,
    );
    expect(await db.productDao.getProduct('coffee'), isNull);
  });
}

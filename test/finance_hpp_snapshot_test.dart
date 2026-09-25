import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  test('old sales without HPP snapshots are not repriced by menu edits', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final paidAt = DateTime(2026, 9, 26, 12);

    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'coffee',
        outletId: 'outlet',
        name: 'Kopi Susu',
        price: '20000',
        cogs: const Value('5000'),
      ),
    );
    await database.orderDao.createOrder(
      OrdersCompanion.insert(
        id: 'old-order',
        outletId: 'outlet',
        orderNumber: 'INV-OLD',
        type: 'takeaway',
        status: 'paid',
        cashierId: 'owner',
        cashierName: 'Owner',
        total: const Value('40000'),
        paidAt: Value(paidAt),
      ),
    );
    await database.orderDao.addOrderItem(
      OrderItemsCompanion.insert(
        id: 'old-item',
        orderId: 'old-order',
        productId: 'coffee',
        productName: 'Kopi Susu',
        unitPrice: '20000',
        quantity: '2',
        subtotal: '40000',
      ),
    );

    final before = await database.financeDao.getOutletSummary(
      'outlet', DateTime(2026, 9, 26), DateTime(2026, 9, 26, 23, 59, 59));
    expect(before.cogs, 0);
    expect(before.hasReliableHpp, isFalse);

    await (database.update(database.products)
          ..where((product) => product.id.equals('coffee')))
        .write(const ProductsCompanion(cogs: Value('7000')));

    final after = await database.financeDao.getOutletSummary(
      'outlet', DateTime(2026, 9, 26), DateTime(2026, 9, 26, 23, 59, 59));
    expect(after.cogs, 0);
    expect(after.hasReliableHpp, isFalse);

    await database.orderDao.createOrder(
      OrdersCompanion.insert(
        id: 'new-order',
        outletId: 'outlet',
        orderNumber: 'INV-NEW',
        type: 'takeaway',
        status: 'paid',
        cashierId: 'owner',
        cashierName: 'Owner',
        total: const Value('20000'),
        paidAt: Value(paidAt),
      ),
    );
    await database.orderDao.addOrderItem(
      OrderItemsCompanion.insert(
        id: 'new-item',
        orderId: 'new-order',
        productId: 'coffee',
        productName: 'Kopi Susu',
        unitPrice: '20000',
        unitCogs: const Value('7000'),
        quantity: '1',
        subtotal: '20000',
      ),
    );

    final mixed = await database.financeDao.getOutletSummary(
      'outlet', DateTime(2026, 9, 26), DateTime(2026, 9, 26, 23, 59, 59));
    expect(mixed.cogs, 7000);
    expect(mixed.soldQuantity, 3);
    expect(mixed.hppCoveredQuantity, 1);
    expect(mixed.hasReliableHpp, isFalse);
  });
}

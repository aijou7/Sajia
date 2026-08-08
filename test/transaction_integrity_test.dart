import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/local/daos/product_dao.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('conditional stock decrement prevents concurrent oversell', () async {
    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'product-stock',
        outletId: 'outlet-1',
        name: 'Ayam Geprek',
        price: '18000',
        trackStock: const Value(true),
        stock: const Value('2'),
        isSynced: const Value(true),
      ),
    );

    Future<Object> attemptSale() async {
      try {
        return await database.productDao.decrementStock('product-stock', 2);
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait([attemptSale(), attemptSale()]);

    expect(results.where((result) => result == true), hasLength(1));
    expect(
      results.whereType<StockValidationException>(),
      hasLength(1),
    );

    final product = await database.productDao.getProduct('product-stock');
    expect(double.parse(product!.stock), 0);
    expect(product.isSynced, isFalse);
  });

  test('stock decrement rejects invalid quantities without changing stock',
      () async {
    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'product-invalid-qty',
        outletId: 'outlet-1',
        name: 'Kopi',
        price: '12000',
        trackStock: const Value(true),
        stock: const Value('5'),
      ),
    );

    await expectLater(
      database.productDao.decrementStock('product-invalid-qty', 0),
      throwsArgumentError,
    );

    final product = await database.productDao.getProduct('product-invalid-qty');
    expect(double.parse(product!.stock), 5);
  });

  test('voiding a paid order restores tracked stock and queues it once',
      () async {
    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'product-void',
        outletId: 'outlet-1',
        name: 'Nasi Goreng',
        price: '20000',
        trackStock: const Value(true),
        stock: const Value('3'),
        isSynced: const Value(true),
      ),
    );
    await database.orderDao.createOrder(
      OrdersCompanion.insert(
        id: 'order-paid',
        outletId: 'outlet-1',
        orderNumber: 'INV-001',
        type: 'dine_in',
        status: 'paid',
        cashierId: 'cashier-1',
        cashierName: 'Kasir',
        total: const Value('60000'),
        isSynced: const Value(true),
      ),
    );
    await database.orderDao.addOrderItem(
      OrderItemsCompanion.insert(
        id: 'item-1',
        orderId: 'order-paid',
        productId: 'product-void',
        productName: 'Nasi Goreng',
        unitPrice: '20000',
        quantity: '1',
        subtotal: '20000',
      ),
    );
    await database.orderDao.addOrderItem(
      OrderItemsCompanion.insert(
        id: 'item-2',
        orderId: 'order-paid',
        productId: 'product-void',
        productName: 'Nasi Goreng',
        unitPrice: '20000',
        quantity: '2',
        subtotal: '40000',
      ),
    );

    await database.orderDao.voidOrder('order-paid', 'Salah input', 'manager-1');
    await database.orderDao.voidOrder('order-paid', 'Tap kedua', 'manager-1');

    final product = await database.productDao.getProduct('product-void');
    expect(double.parse(product!.stock), 6);
    expect(product.isSynced, isFalse);

    final order = await database.orderDao.getOrder('order-paid');
    expect(order!.status, 'void');
    expect(order.voidReason, 'Salah input');
    expect(order.isSynced, isFalse);

    final pending = await database.select(database.syncQueue).get();
    final reversals = pending
        .where((item) =>
            item.syncTableName == 'stock_reversals' &&
            item.recordId == 'order-paid')
        .toList();
    expect(reversals, hasLength(1));
    expect(reversals.single.operation, 'reverse');
    final payload =
        Map<String, dynamic>.from(jsonDecode(reversals.single.payload) as Map);
    expect(payload['order_id'], 'order-paid');
    expect(payload['outlet_id'], 'outlet-1');
  });

  test('deactivating staff updates timestamp and marks row unsynced', () async {
    final oldUpdatedAt = DateTime(2020);
    await database.sessionDao.upsertUser(
      UsersCompanion.insert(
        id: 'cashier-1',
        name: 'Kasir Lama',
        pin: 'hashed-pin',
        role: 'cashier',
        outletId: 'outlet-1',
        updatedAt: Value(oldUpdatedAt),
        isSynced: const Value(true),
      ),
    );

    await database.sessionDao.deactivateUser('cashier-1');

    final user = await (database.select(database.users)
          ..where((row) => row.id.equals('cashier-1')))
        .getSingle();
    expect(user.isActive, isFalse);
    expect(user.isSynced, isFalse);
    expect(user.updatedAt.isAfter(oldUpdatedAt), isTrue);
  });
}

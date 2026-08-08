import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  test('empty sales summary keeps monetary values as doubles', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final date = DateTime(2026, 7, 26);
    final summary = await database.orderDao.getSalesSummaryForScope(
      null,
      DateTime(date.year, date.month, date.day),
      DateTime(date.year, date.month, date.day, 23, 59, 59),
    );

    expect(summary['orderCount'], 0);
    expect(summary['totalRevenue'], 0.0);
    expect(summary['totalCash'], 0.0);
    expect(summary['totalQris'], 0.0);
    expect(summary['avgOrderValue'], 0.0);
    expect(summary['avgOrderValue'], isA<double>());
  });

  test('sales report is grouped by product category', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final paidAt = DateTime(2026, 8, 6, 12);

    await database.productDao.upsertCategory(
      CategoriesCompanion.insert(
        id: 'category-food',
        outletId: 'outlet-1',
        name: 'Makanan',
      ),
    );
    await database.productDao.upsertProduct(
      ProductsCompanion.insert(
        id: 'product-rice',
        outletId: 'outlet-1',
        categoryId: const Value('category-food'),
        name: 'Nasi Goreng',
        price: '20000',
      ),
    );
    await database.orderDao.createOrder(
      OrdersCompanion.insert(
        id: 'order-1',
        outletId: 'outlet-1',
        orderNumber: 'INV-001',
        type: 'dine_in',
        status: 'paid',
        cashierId: 'owner-1',
        cashierName: 'Owner',
        total: const Value('40000'),
        paidAt: Value(paidAt),
      ),
    );
    await database.orderDao.addOrderItem(
      OrderItemsCompanion.insert(
        id: 'item-1',
        orderId: 'order-1',
        productId: 'product-rice',
        productName: 'Nasi Goreng',
        unitPrice: '20000',
        quantity: '2',
        subtotal: '40000',
      ),
    );

    final categories = await database.orderDao.getSalesByCategoryForScope(
      ['outlet-1'],
      DateTime(2026, 8, 6),
      DateTime(2026, 8, 6, 23, 59, 59),
    );

    expect(categories, hasLength(1));
    expect(categories.single['name'], 'Makanan');
    expect(categories.single['productCount'], 1);
    expect(categories.single['qty'], 2.0);
    expect(categories.single['revenue'], 40000.0);
  });
}

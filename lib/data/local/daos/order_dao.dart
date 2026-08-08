import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'order_dao.g.dart';

@DriftAccessor(tables: [Orders, OrderItems, RestaurantTables])
class OrderDao extends DatabaseAccessor<AppDatabase> with _$OrderDaoMixin {
  OrderDao(super.db);

  // ─── ORDERS ───────────────────────────────────────────────

  Stream<List<Order>> watchActiveOrders(String outletId) => (select(orders)
        ..where(
          (o) =>
              o.outletId.equals(outletId) &
              o.status.isIn(['open', 'in_kitchen', 'ready', 'hold']),
        )
        ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
      .watch();

  Stream<List<Order>> watchOrdersByDate(String outletId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (select(orders)
          ..where(
            (o) =>
                o.outletId.equals(outletId) &
                o.createdAt.isBetweenValues(start, end),
          )
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .watch();
  }

  Future<Order?> getOrder(String id) =>
      (select(orders)..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<Order?> getOrderByTable(String tableId) => (select(orders)
        ..where(
          (o) =>
              o.tableId.equals(tableId) &
              o.status.isIn(['open', 'in_kitchen', 'ready']),
        ))
      .getSingleOrNull();

  Future<String> createOrder(OrdersCompanion order) async {
    await into(orders).insert(order);
    return order.id.value;
  }

  Future<void> updateOrderStatus(String id, String status) =>
      (update(orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  Future<void> updateOrder(String id, OrdersCompanion companion) =>
      (update(orders)..where((o) => o.id.equals(id))).write(companion);

  /// Selesaikan pembayaran — atomic update order + meja
  Future<void> completePayment({
    required String orderId,
    required String paymentMethod,
    required double paidAmount,
    required double changeAmount,
    String? paymentRef,
    String? tableId,
  }) async {
    await transaction(() async {
      // Update order jadi paid
      await (update(orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value('paid'),
          paymentMethod: Value(paymentMethod),
          paidAmount: Value(paidAmount.toString()),
          changeAmount: Value(changeAmount.toString()),
          paymentRef: Value(paymentRef),
          paidAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

      // Bebaskan meja
      if (tableId != null) {
        await (update(restaurantTables)..where((t) => t.id.equals(tableId)))
            .write(
          RestaurantTablesCompanion(
            status: const Value('available'),
            currentOrderId: const Value(null),
            updatedAt: Value(DateTime.now()),
            isSynced: const Value(false),
          ),
        );
      }
    });
  }

  /// Void order
  Future<void> voidOrder(String orderId, String reason, String voidedBy) async {
    final order = await getOrder(orderId);
    if (order == null) return;

    await transaction(() async {
      await (update(orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value('void'),
          voidReason: Value(reason),
          voidedBy: Value(voidedBy),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

      // Bebaskan meja kalau ada
      if (order.tableId != null) {
        await (update(restaurantTables)
              ..where((t) => t.id.equals(order.tableId!)))
            .write(
          RestaurantTablesCompanion(
            status: const Value('available'),
            currentOrderId: const Value(null),
            updatedAt: Value(DateTime.now()),
            isSynced: const Value(false),
          ),
        );
      }
    });
  }

  Future<List<Order>> getUnsyncedOrders() =>
      (select(orders)..where((o) => o.isSynced.equals(false))).get();

  Future<void> markOrderSynced(String id) =>
      (update(orders)..where((o) => o.id.equals(id)))
          .write(const OrdersCompanion(isSynced: Value(true)));

  // ─── ORDER ITEMS ──────────────────────────────────────────

  Stream<List<OrderItem>> watchOrderItems(String orderId) => (select(orderItems)
        ..where((i) => i.orderId.equals(orderId))
        ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
      .watch();

  Future<List<OrderItem>> getOrderItems(String orderId) =>
      (select(orderItems)..where((i) => i.orderId.equals(orderId))).get();

  Future<void> addOrderItem(OrderItemsCompanion item) =>
      into(orderItems).insert(item);

  Future<void> updateItemQuantity(String itemId, double qty) =>
      (update(orderItems)..where((i) => i.id.equals(itemId))).write(
        OrderItemsCompanion(
          quantity: Value(qty.toString()),
          isSynced: const Value(false),
        ),
      );

  Future<void> removeOrderItem(String itemId) =>
      (delete(orderItems)..where((i) => i.id.equals(itemId))).go();

  Future<void> updateItemStatus(String itemId, String status) =>
      (update(orderItems)..where((i) => i.id.equals(itemId))).write(
        OrderItemsCompanion(
          status: Value(status),
          isSynced: const Value(false),
        ),
      );

  Future<List<OrderItem>> getUnsyncedItems() =>
      (select(orderItems)..where((i) => i.isSynced.equals(false))).get();

  Future<void> upsertOrderItem(OrderItemsCompanion item) =>
      into(orderItems).insertOnConflictUpdate(item);

  Future<void> markItemSynced(String id) =>
      (update(orderItems)..where((i) => i.id.equals(id)))
          .write(const OrderItemsCompanion(isSynced: Value(true)));

  // ─── RESTAURANT TABLES ────────────────────────────────────

  Stream<List<RestaurantTable>> watchTables(String outletId) =>
      (select(restaurantTables)
            ..where((t) => t.outletId.equals(outletId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.area),
              (t) => OrderingTerm.asc(t.tableLabel),
            ]))
          .watch();

  Future<void> upsertTable(RestaurantTablesCompanion table) =>
      into(restaurantTables).insertOnConflictUpdate(table);
  Future<void> deleteTable(String tableId) =>
      (delete(restaurantTables)..where((t) => t.id.equals(tableId))).go();

  Future<void> occupyTable(String tableId, String orderId) =>
      (update(restaurantTables)..where((t) => t.id.equals(tableId))).write(
        RestaurantTablesCompanion(
          status: const Value('occupied'),
          currentOrderId: Value(orderId),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  Future<List<RestaurantTable>> getUnsyncedTables() =>
      (select(restaurantTables)..where((t) => t.isSynced.equals(false))).get();

  Future<void> markTableSynced(String id) =>
      (update(restaurantTables)..where((t) => t.id.equals(id)))
          .write(const RestaurantTablesCompanion(isSynced: Value(true)));

  // ─── REPORTING QUERIES ────────────────────────────────────

  /// Summary penjualan untuk range tanggal tertentu
  Future<Map<String, dynamic>> getSalesSummary(
    String outletId,
    DateTime from,
    DateTime to,
  ) =>
      getSalesSummaryForScope([outletId], from, to);

  /// Summary penjualan untuk laporan.
  ///
  /// Kalau [outletIds] null, data digabung dari semua cabang lokal.
  Future<Map<String, dynamic>> getSalesSummaryForScope(
    List<String>? outletIds,
    DateTime from,
    DateTime to,
  ) async {
    final paidOrders = await _getPaidOrdersForReport(outletIds, from, to);

    double totalRevenue = 0;
    double totalCash = 0;
    double totalQris = 0;
    int orderCount = paidOrders.length;

    for (final o in paidOrders) {
      final total = double.tryParse(o.total) ?? 0;
      totalRevenue += total;
      if (o.paymentMethod == 'cash') totalCash += total;
      if (o.paymentMethod == 'qris') totalQris += total;
    }

    return {
      'totalRevenue': totalRevenue,
      'totalCash': totalCash,
      'totalQris': totalQris,
      'orderCount': orderCount,
      'avgOrderValue': orderCount > 0 ? totalRevenue / orderCount : 0.0,
    };
  }

  /// Top produk terlaris dalam range tanggal
  Future<List<Map<String, dynamic>>> getTopProducts(
    String outletId,
    DateTime from,
    DateTime to, {
    int limit = 10,
  }) =>
      getTopProductsForScope([outletId], from, to, limit: limit);

  /// Top produk untuk laporan.
  ///
  /// Kalau [outletIds] null, data digabung dari semua cabang lokal.
  Future<List<Map<String, dynamic>>> getTopProductsForScope(
    List<String>? outletIds,
    DateTime from,
    DateTime to, {
    int limit = 10,
  }) async {
    final paidOrders = await _getPaidOrdersForReport(outletIds, from, to);

    final orderIds = paidOrders.map((o) => o.id).toList();
    if (orderIds.isEmpty) return [];

    final items = await (select(orderItems)
          ..where((i) => i.orderId.isIn(orderIds)))
        .get();

    // Group by product name
    final Map<String, Map<String, dynamic>> productMap = {};
    for (final item in items) {
      final key = item.productId;
      if (!productMap.containsKey(key)) {
        productMap[key] = {
          'productId': item.productId,
          'name': item.productName,
          'qty': 0.0,
          'revenue': 0.0,
        };
      }
      productMap[key]!['qty'] = (productMap[key]!['qty'] as double) +
          (double.tryParse(item.quantity) ?? 0);
      productMap[key]!['revenue'] = (productMap[key]!['revenue'] as double) +
          (double.tryParse(item.subtotal) ?? 0);
    }

    final sorted = productMap.values.toList()
      ..sort((a, b) => (b['qty'] as double).compareTo(a['qty'] as double));

    return sorted.take(limit).toList();
  }

  /// Rekap penjualan yang dipisahkan berdasarkan kategori produk.
  Future<List<Map<String, dynamic>>> getSalesByCategoryForScope(
    List<String>? outletIds,
    DateTime from,
    DateTime to,
  ) async {
    final paidOrders = await _getPaidOrdersForReport(outletIds, from, to);
    final orderIds = paidOrders.map((order) => order.id).toList();
    if (orderIds.isEmpty) return [];

    final items = await (select(orderItems)
          ..where((item) => item.orderId.isIn(orderIds)))
        .get();
    if (items.isEmpty) return [];

    final productIds = items.map((item) => item.productId).toSet().toList();
    final productRows =
        await (attachedDatabase.select(attachedDatabase.products)
              ..where((product) => product.id.isIn(productIds)))
            .get();
    final productsById = {
      for (final product in productRows) product.id: product
    };

    final categoryIds = productRows
        .map((product) => product.categoryId)
        .whereType<String>()
        .toSet()
        .toList();
    final categoryRows = categoryIds.isEmpty
        ? <Category>[]
        : await (attachedDatabase.select(attachedDatabase.categories)
              ..where((category) => category.id.isIn(categoryIds)))
            .get();
    final categoriesById = {
      for (final category in categoryRows) category.id: category,
    };

    final grouped = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final product = productsById[item.productId];
      final categoryId = product?.categoryId;
      final category = categoryId == null ? null : categoriesById[categoryId];
      final key = product == null
          ? '__deleted__'
          : (category == null
              ? '__uncategorized__'
              : 'category:${category.name.trim().toLowerCase()}');
      final name = product == null
          ? 'Produk dihapus'
          : (category?.name ?? 'Tanpa kategori');

      grouped.putIfAbsent(key, () {
        return {
          'categoryId': category?.id,
          'name': name,
          'colorHex': category?.colorHex ?? '#6B7280',
          'qty': 0.0,
          'revenue': 0.0,
          '_productIds': <String>{},
        };
      });

      grouped[key]!['qty'] = (grouped[key]!['qty'] as double) +
          (double.tryParse(item.quantity) ?? 0);
      grouped[key]!['revenue'] = (grouped[key]!['revenue'] as double) +
          (double.tryParse(item.subtotal) ?? 0);
      (grouped[key]!['_productIds'] as Set<String>).add(item.productId);
    }

    final result = grouped.values.map((row) {
      final productIds = row.remove('_productIds') as Set<String>;
      row['productCount'] = productIds.length;
      return row;
    }).toList()
      ..sort(
          (a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

    return result;
  }

  Future<List<Order>> _getPaidOrdersForReport(
    List<String>? outletIds,
    DateTime from,
    DateTime to,
  ) {
    if (outletIds != null && outletIds.isEmpty) return Future.value([]);
    return (select(orders)
          ..where((o) {
            final paidInRange =
                o.status.equals('paid') & o.paidAt.isBetweenValues(from, to);
            return outletIds == null
                ? paidInRange
                : o.outletId.isIn(outletIds) & paidInRange;
          }))
        .get();
  }
}

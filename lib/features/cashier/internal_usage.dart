import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../domain/entities/entities.dart';
import '../../domain/ingredient_inventory.dart';

/// An internal usage is durable locally without creating a paid sale or a
/// cash movement. Its fixed ID is replayed by sync until Cloud acknowledges it.
Future<String> enqueueInternalUsage(
    {required AppDatabase db,
    required Cart cart,
    required String outletId,
    required String purpose,
    String? id}) async {
  if (cart.items.isEmpty ||
      !const {'rnd', 'personal', 'waste'}.contains(purpose)) {
    throw ArgumentError('Pemakaian tidak valid.');
  }
  final items = aggregateUsageItems(cart.items
      .map((item) => (productId: item.productId, quantity: item.quantity)));
  final usageId = id ?? const Uuid().v4();
  await db.transaction(() async {
    for (final item in items) {
      final product =
          await db.productDao.getProduct(item['product_id'] as String);
      if (product == null || product.outletId != outletId) {
        throw StateError('Menu tidak lagi tersedia di cabang ini.');
      }
      await db.productDao
          .decrementStock(product.id, item['quantity'] as double);
    }
    await db.syncDao.enqueue(
        tableName: 'internal_usage',
        recordId: usageId,
        operation: 'consume',
        payload: {
          'outlet_id': outletId,
          'purpose': purpose,
          'items': items,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'note': cart.notes,
        });
  });
  return usageId;
}

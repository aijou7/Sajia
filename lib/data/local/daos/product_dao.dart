import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'product_dao.g.dart';

/// Raised when a stock-tracked product can no longer satisfy a sale.
///
/// The conditional SQLite update in [ProductDao.decrementStock] is the source
/// of truth. Callers must not rely on an earlier UI stock check because two
/// checkouts may race between that check and the actual write.
class StockValidationException implements Exception {
  const StockValidationException({
    required this.productId,
    required this.requested,
    this.available,
  });

  final String productId;
  final double requested;
  final double? available;

  bool get productMissing => available == null;

  @override
  String toString() => productMissing
      ? 'Product $productId is no longer available'
      : 'Insufficient stock for $productId: requested $requested, '
          'available $available';
}

@DriftAccessor(tables: [Products, Categories, ProductVariants])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  // CATEGORIES
  Stream<List<Category>> watchCategories(String outletId) => (select(categories)
        ..where((c) => c.outletId.equals(outletId) & c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .watch();

  Future<List<Category>> getCategories(String outletId) => (select(categories)
        ..where((c) => c.outletId.equals(outletId) & c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .get();

  Future<void> upsertCategory(CategoriesCompanion cat) =>
      into(categories).insertOnConflictUpdate(cat);

  Future<void> deleteCategory(String id) async {
    await transaction(() async {
      await (update(products)
            ..where((product) => product.categoryId.equals(id)))
          .write(ProductsCompanion(
        categoryId: const Value(null),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ));
      await (update(categories)..where((category) => category.id.equals(id)))
          .write(CategoriesCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ));
    });
  }

  // PRODUCTS
  Stream<List<Product>> watchProducts(String outletId) => (select(products)
        ..where((p) => p.outletId.equals(outletId))
        ..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]))
      .watch();

  Stream<List<Product>> watchAvailableProducts(String outletId) =>
      (select(products)
            ..where(
                (p) => p.outletId.equals(outletId) & p.isAvailable.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]))
          .watch();

  Future<Product?> getProduct(String id) =>
      (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<void> upsertProduct(ProductsCompanion product) =>
      into(products).insertOnConflictUpdate(product);

  Future<void> toggleAvailability(String id, bool isAvailable) =>
      (update(products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          isAvailable: Value(isAvailable),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  Future<void> deleteProduct(String id) async {
    await transaction(() async {
      await (delete(productVariants)..where((v) => v.productId.equals(id)))
          .go();
      await (delete(products)..where((p) => p.id.equals(id))).go();
    });
  }

  Future<void> updateStock(String id, double newStock) =>
      (update(products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          stock: Value(newStock.toString()),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  /// Atomically validates and decrements stock for one product.
  ///
  /// Returns `true` when the product is stock-tracked and was decremented, or
  /// `false` when stock tracking is disabled. A missing product or insufficient
  /// stock throws [StockValidationException]. The `WHERE stock >= quantity`
  /// condition prevents two concurrent checkouts from both consuming the same
  /// remaining stock.
  Future<bool> decrementStock(String productId, double qty) async {
    if (!qty.isFinite || qty <= 0) {
      throw ArgumentError.value(
          qty, 'qty', 'must be finite and greater than 0');
    }

    final product = await getProduct(productId);
    if (product == null) {
      throw StockValidationException(
        productId: productId,
        requested: qty,
      );
    }
    if (!product.trackStock) return false;

    final affected = await customUpdate(
      '''
      UPDATE products
      SET stock = CAST(CAST(stock AS REAL) - ? AS TEXT),
          updated_at = ?,
          is_synced = 0
      WHERE id = ?
        AND track_stock = 1
        AND CAST(stock AS REAL) >= ?
      ''',
      variables: [
        Variable<double>(qty),
        Variable<DateTime>(DateTime.now()),
        Variable<String>(productId),
        Variable<double>(qty),
      ],
      updates: {products},
    );

    if (affected == 1) return true;

    final latest = await getProduct(productId);
    if (latest != null && !latest.trackStock) return false;
    throw StockValidationException(
      productId: productId,
      requested: qty,
      available: latest == null ? null : (double.tryParse(latest.stock) ?? 0.0),
    );
  }

  /// Restores stock as part of an already-open database transaction.
  ///
  /// The caller is responsible for idempotency (for example by transitioning
  /// an order from `paid` to `void` only once).
  Future<double?> restoreStock(String productId, double qty) async {
    if (!qty.isFinite || qty <= 0) {
      throw ArgumentError.value(
          qty, 'qty', 'must be finite and greater than 0');
    }

    final affected = await customUpdate(
      '''
      UPDATE products
      SET stock = CAST(CAST(stock AS REAL) + ? AS TEXT),
          updated_at = ?,
          is_synced = 0
      WHERE id = ? AND track_stock = 1
      ''',
      variables: [
        Variable<double>(qty),
        Variable<DateTime>(DateTime.now()),
        Variable<String>(productId),
      ],
      updates: {products},
    );
    if (affected != 1) return null;

    final restored = await getProduct(productId);
    return restored == null ? null : double.tryParse(restored.stock);
  }

  Future<List<Product>> getLowStockProducts(String outletId) async {
    final all = await (select(products)
          ..where(
              (p) => p.outletId.equals(outletId) & p.trackStock.equals(true)))
        .get();
    return all.where((p) {
      final stock = double.tryParse(p.stock) ?? 0;
      final threshold = double.tryParse(p.lowStockAlert) ?? 5;
      return stock <= threshold;
    }).toList();
  }

  // VARIANTS
  Stream<List<ProductVariant>> watchVariants(String productId) =>
      (select(productVariants)..where((v) => v.productId.equals(productId)))
          .watch();

  Future<List<ProductVariant>> getVariants(String productId) =>
      (select(productVariants)..where((v) => v.productId.equals(productId)))
          .get();

  Future<void> upsertVariant(ProductVariantsCompanion variant) =>
      into(productVariants).insertOnConflictUpdate(variant);

  Future<void> deleteVariant(String id) =>
      (delete(productVariants)..where((v) => v.id.equals(id))).go();

  // SYNC
  Future<List<Product>> getUnsyncedProducts() =>
      (select(products)..where((p) => p.isSynced.equals(false))).get();

  Future<List<Category>> getUnsyncedCategories() =>
      (select(categories)..where((c) => c.isSynced.equals(false))).get();

  Future<List<ProductVariant>> getUnsyncedVariants() =>
      (select(productVariants)..where((v) => v.isSynced.equals(false))).get();

  Future<void> markProductSynced(String id) =>
      (update(products)..where((p) => p.id.equals(id)))
          .write(const ProductsCompanion(isSynced: Value(true)));

  Future<void> markCategorySynced(String id) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(isSynced: Value(true)));

  Future<void> markVariantSynced(String id) =>
      (update(productVariants)..where((v) => v.id.equals(id)))
          .write(const ProductVariantsCompanion(isSynced: Value(true)));
}

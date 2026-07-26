import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'product_dao.g.dart';

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

  Future<void> deleteCategory(String id) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(isActive: Value(false)));

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

  Future<void> updateStock(String id, double newStock) =>
      (update(products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          stock: Value(newStock.toString()),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  Future<void> decrementStock(String productId, double qty) async {
    final product = await getProduct(productId);
    if (product == null || !product.trackStock) return;
    final currentStock = double.tryParse(product.stock) ?? 0;
    final newStock = (currentStock - qty).clamp(0.0, double.infinity);
    await updateStock(productId, newStock);
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

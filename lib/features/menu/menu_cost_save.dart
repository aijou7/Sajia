import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../domain/costing.dart';

/// Resolve HPP from the latest local row while the caller holds a write
/// transaction. A form can remain open while dashboard HPP arrives via sync.
Future<({String cogs, bool ownerManaged})> resolveMenuCostForSave({
  required AppDatabase db,
  required String outletId,
  required Product? openedProduct,
  required bool recipeEdited,
  required List<CostingComponent> recipeLines,
  required String enteredCogs,
}) async {
  final outlet = await (db.select(db.outlets)
        ..where((row) => row.id.equals(outletId)))
      .getSingleOrNull();
  if (outlet == null) throw StateError('Outlet no longer exists');

  Product? currentProduct;
  if (openedProduct != null) {
    currentProduct = await db.productDao.getProduct(openedProduct.id);
    if (currentProduct == null || currentProduct.outletId != outletId) {
      throw StateError('Product no longer belongs to this outlet');
    }
  }

  final profileManaged = currentProduct != null &&
      await db.costingDao.isOwnerManagedProduct(currentProduct.id);
  final ownerManaged = outlet.cloudExpiry != null || profileManaged;
  final entered = enteredCogs.trim();
  final openedCogs = openedProduct?.cogs == '0' ? '' : openedProduct?.cogs;

  if (ownerManaged) {
    if (currentProduct != null) {
      if (recipeEdited || entered != openedCogs) {
        throw StateError('Dashboard-managed HPP changed in the form');
      }
      return (cogs: currentProduct.cogs, ownerManaged: true);
    }
    final hpp = double.tryParse(entered);
    if (hpp == null || !hpp.isFinite || hpp <= 0) {
      throw StateError('Initial HPP must be greater than zero');
    }
    return (cogs: entered, ownerManaged: true);
  }

  if (recipeEdited && recipeLines.isNotEmpty) {
    return (
      cogs: totalCosting(recipeLines).round().toString(),
      ownerManaged: false,
    );
  }
  // An unchanged cost field is not permission to revert a newer local value.
  if (!recipeEdited && currentProduct != null && entered == openedCogs) {
    return (cogs: currentProduct.cogs, ownerManaged: false);
  }
  return (cogs: entered.isEmpty ? '0' : entered, ownerManaged: false);
}

import 'package:drift/drift.dart';

import '../../../domain/costing.dart';
import '../app_database.dart';

/// Local persistence for per-menu recipe/HPP lines.
///
/// This is intentionally a small custom table instead of a generated Drift
/// table so old encrypted databases can receive the feature additively.
class CostingDao extends DatabaseAccessor<AppDatabase> {
  CostingDao(super.db);

  Future<List<CostingComponent>> getForProduct(String productId) async {
    final rows = await customSelect(
      '''
      SELECT id, outlet_id, product_id, material_name, package_quantity,
             package_unit, package_price, recipe_quantity, recipe_unit,
             updated_at, is_synced
      FROM product_cost_components
      WHERE product_id = ?
      ORDER BY rowid ASC
      ''',
      variables: [Variable<String>(productId)],
    ).get();
    return rows.map(_mapRow).toList();
  }

  Future<List<CostingComponent>> getUnsynced() async {
    final rows = await customSelect(
      '''
      SELECT id, outlet_id, product_id, material_name, package_quantity,
             package_unit, package_price, recipe_quantity, recipe_unit,
             updated_at, is_synced
      FROM product_cost_components
      WHERE is_synced = 0
      ORDER BY updated_at ASC
      ''',
    ).get();
    return rows.map(_mapRow).toList();
  }

  Future<void> replaceForProduct({
    required String outletId,
    required String productId,
    required List<CostingComponent> components,
  }) async {
    final previous = await getForProduct(productId);
    final nextIds = components.map((item) => item.id).toSet();

    for (final removed in previous.where((item) => !nextIds.contains(item.id))) {
      await customStatement(
        'DELETE FROM product_cost_components WHERE id = ?',
        [removed.id],
      );
      await db.syncDao.enqueue(
        tableName: 'product_cost_components',
        recordId: removed.id,
        operation: 'delete',
        payload: {'outlet_id': outletId, 'product_id': productId},
      );
    }

    for (final component in components) {
      await customStatement(
        '''
        INSERT INTO product_cost_components (
          id, outlet_id, product_id, material_name, package_quantity,
          package_unit, package_price, recipe_quantity, recipe_unit,
          updated_at, is_synced
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        ON CONFLICT(id) DO UPDATE SET
          outlet_id = excluded.outlet_id,
          product_id = excluded.product_id,
          material_name = excluded.material_name,
          package_quantity = excluded.package_quantity,
          package_unit = excluded.package_unit,
          package_price = excluded.package_price,
          recipe_quantity = excluded.recipe_quantity,
          recipe_unit = excluded.recipe_unit,
          updated_at = excluded.updated_at,
          is_synced = 0
        ''',
        [
          component.id,
          outletId,
          productId,
          component.materialName,
          component.packageQuantity.toString(),
          component.packageUnit.name,
          component.packagePrice.toString(),
          component.recipeQuantity.toString(),
          component.recipeUnit.name,
          component.updatedAt.toUtc().toIso8601String(),
        ],
      );
      await db.syncDao.cancelPendingDelete(
        tableName: 'product_cost_components',
        recordId: component.id,
      );
    }
  }

  Future<void> upsertFromRemote(
    CostingComponent component, {
    bool synced = true,
  }) async {
    await customStatement(
      '''
      INSERT INTO product_cost_components (
        id, outlet_id, product_id, material_name, package_quantity,
        package_unit, package_price, recipe_quantity, recipe_unit,
        updated_at, is_synced
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        outlet_id = excluded.outlet_id,
        product_id = excluded.product_id,
        material_name = excluded.material_name,
        package_quantity = excluded.package_quantity,
        package_unit = excluded.package_unit,
        package_price = excluded.package_price,
        recipe_quantity = excluded.recipe_quantity,
        recipe_unit = excluded.recipe_unit,
        updated_at = excluded.updated_at,
          is_synced = excluded.is_synced
      ''',
      [
        component.id,
        component.outletId,
        component.productId,
        component.materialName,
        component.packageQuantity.toString(),
        component.packageUnit.name,
        component.packagePrice.toString(),
        component.recipeQuantity.toString(),
        component.recipeUnit.name,
        component.updatedAt.toUtc().toIso8601String(),
        synced ? 1 : 0,
      ],
    );
  }

  Future<void> markSynced(String id) async {
    await customStatement(
      'UPDATE product_cost_components SET is_synced = 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> deleteComponent(String id, {bool enqueueSync = true}) async {
    final existing = await customSelect(
      'SELECT outlet_id, product_id FROM product_cost_components WHERE id = ?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    await customStatement('DELETE FROM product_cost_components WHERE id = ?', [id]);
    if (enqueueSync && existing != null) {
      await db.syncDao.enqueue(
        tableName: 'product_cost_components',
        recordId: id,
        operation: 'delete',
        payload: {
          'outlet_id': existing.read<String>('outlet_id'),
          'product_id': existing.read<String>('product_id'),
        },
      );
    }
  }

  Future<void> deleteForOutletIds(Iterable<String> outletIds) async {
    for (final outletId in outletIds) {
      await customStatement(
        'DELETE FROM product_cost_components WHERE outlet_id = ?',
        [outletId],
      );
    }
  }

  CostingComponent _mapRow(QueryRow row) => CostingComponent(
        id: row.read<String>('id'),
        outletId: row.read<String>('outlet_id'),
        productId: row.read<String>('product_id'),
        materialName: row.read<String>('material_name'),
        packageQuantity: double.tryParse(row.read<String>('package_quantity')) ?? 0,
        packageUnit: costingUnitFromStorage(row.read<String>('package_unit')),
        packagePrice: double.tryParse(row.read<String>('package_price')) ?? 0,
        recipeQuantity: double.tryParse(row.read<String>('recipe_quantity')) ?? 0,
        recipeUnit: costingUnitFromStorage(row.read<String>('recipe_unit')),
        updatedAt: DateTime.tryParse(row.read<String>('updated_at')) ?? DateTime.now(),
        isSynced: row.read<int>('is_synced') != 0,
      );
}

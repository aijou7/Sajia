import '../../domain/costing.dart';
import '../local/app_database.dart';

/// Keeps owner-managed recipes authoritative across offline APK writes.
/// Network operations are passed in so the same decisions can be tested
/// without a live Supabase project.
class CostingSyncCoordinator {
  final AppDatabase db;

  const CostingSyncCoordinator(this.db);

  Future<Set<String>> refreshManagedProfiles(
    Future<Map<String, String>> Function() fetchProfiles,
  ) async {
    // Do not clear the durable cache on a failed or partial server fetch.
    final profiles = await fetchProfiles();
    await db.costingDao.replaceManagedProfiles(profiles);
    return profiles.keys.toSet();
  }

  Future<void> resolvePendingDelete({
    required int queueId,
    required String componentId,
    required String? productId,
    required Set<String> managedProductIds,
    required Future<String?> Function(String) findRemoteProductId,
    required Future<void> Function(String) deleteRemote,
  }) async {
    final resolvedProductId =
        productId ?? await findRemoteProductId(componentId);
    if (resolvedProductId != null &&
        !managedProductIds.contains(resolvedProductId)) {
      await deleteRemote(componentId);
    }
    // If the row is already absent, or its product is dashboard-owned, the
    // old APK deletion is resolved without changing canonical server data.
    await db.syncDao.markDone(queueId);
  }

  Future<bool> pushIfUnmanaged({
    required CostingComponent component,
    required Set<String> managedProductIds,
    required Future<void> Function(CostingComponent) upload,
  }) async {
    if (managedProductIds.contains(component.productId)) return false;
    await upload(component);
    await db.costingDao.markSynced(component.id);
    return true;
  }

  Future<void> applyRemoteSnapshot({
    required Set<String> managedProductIds,
    required List<CostingComponent> remoteComponents,
  }) async {
    final managedRecipes = <String, List<CostingComponent>>{
      for (final id in managedProductIds) id: <CostingComponent>[],
    };
    for (final component in remoteComponents) {
      if (component.id.isEmpty || component.productId.isEmpty) continue;
      if (managedProductIds.contains(component.productId)) {
        managedRecipes[component.productId]!.add(component);
      } else {
        await db.costingDao.upsertFromRemote(component);
      }
    }
    for (final entry in managedRecipes.entries) {
      await db.costingDao.replaceManagedFromRemote(entry.key, entry.value);
    }
  }
}

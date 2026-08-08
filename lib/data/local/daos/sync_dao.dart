import 'dart:convert';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'sync_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<void> enqueue({
    required String tableName,
    required String recordId,
    required String operation, // 'insert' | 'update' | 'delete'
    required Map<String, dynamic> payload,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        syncTableName: tableName,
        recordId: recordId,
        operation: operation,
        payload: jsonEncode(payload),
      ),
    );
  }

  Future<List<SyncQueueData>> getPending({int limit = 50}) => (select(syncQueue)
        ..where((q) => q.retryCount.isSmallerThanValue(5))
        ..orderBy([(q) => OrderingTerm.asc(q.createdAt)])
        ..limit(limit))
      .get();

  Future<void> markDone(int id) =>
      (delete(syncQueue)..where((q) => q.id.equals(id))).go();

  /// Cancels a delete that has not reached the server yet.
  ///
  /// This is used when the same relationship is deliberately created again
  /// while its offline delete is still queued. Without cancelling it, the
  /// delayed delete would win after the new row is pushed.
  Future<void> cancelPendingDelete({
    required String tableName,
    required String recordId,
  }) =>
      (delete(syncQueue)
            ..where(
              (q) =>
                  q.syncTableName.equals(tableName) &
                  q.recordId.equals(recordId) &
                  q.operation.equals('delete'),
            ))
          .go();

  Future<void> markFailed(int id, String error) =>
      (update(syncQueue)..where((q) => q.id.equals(id))).write(
        SyncQueueCompanion(
          retryCount: const Value(
            // increment via custom expression — get current first
            0, // diupdate di SyncService setelah get current value
          ),
          lastRetryAt: Value(DateTime.now()),
          errorMessage: Value(error),
        ),
      );

  Future<void> incrementRetry(int id, String error) async {
    final item = await (select(syncQueue)..where((q) => q.id.equals(id)))
        .getSingleOrNull();
    if (item == null) return;
    await (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        retryCount: Value(item.retryCount + 1),
        lastRetryAt: Value(DateTime.now()),
        errorMessage: Value(error),
      ),
    );
  }

  Future<int> getPendingCount() async {
    final items = await getPending();
    return items.length;
  }

  Future<void> clearAll() => delete(syncQueue).go();
}

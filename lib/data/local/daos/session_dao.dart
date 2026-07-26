import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'session_dao.g.dart';

@DriftAccessor(tables: [Sessions, Users, UserOutletAccesses])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  SessionDao(super.db);

  // ─── SESSIONS (shift) ─────────────────────────────────────

  /// Session aktif untuk kasir ini
  Future<Session?> getActiveSession(String cashierId) => (select(sessions)
        ..where(
          (s) => s.cashierId.equals(cashierId) & s.closedAt.isNull(),
        )
        ..limit(1))
      .getSingleOrNull();

  /// Ada session aktif di outlet ini (siapapun kasirnya)
  Future<Session?> getActiveSessionByOutlet(String outletId) =>
      (select(sessions)
            ..where(
              (s) => s.outletId.equals(outletId) & s.closedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<void> openSession(SessionsCompanion session) =>
      into(sessions).insert(session);

  Future<void> closeSession({
    required String sessionId,
    required double closingCash,
    required double totalCashSales,
    required double totalQrisSales,
    required int totalOrders,
    required int totalVoids,
    String? notes,
  }) =>
      (update(sessions)..where((s) => s.id.equals(sessionId))).write(
        SessionsCompanion(
          closingCash: Value(closingCash.toString()),
          totalCashSales: Value(totalCashSales.toString()),
          totalQrisSales: Value(totalQrisSales.toString()),
          totalOrders: Value(totalOrders),
          totalVoids: Value(totalVoids),
          notes: Value(notes),
          closedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ),
      );

  Stream<List<Session>> watchRecentSessions(String outletId,
          {int limit = 30}) =>
      (select(sessions)
            ..where((s) => s.outletId.equals(outletId))
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(limit))
          .watch();

  Future<List<Session>> getUnsyncedSessions() =>
      (select(sessions)..where((s) => s.isSynced.equals(false))).get();

  Future<void> markSessionSynced(String id) =>
      (update(sessions)..where((s) => s.id.equals(id)))
          .write(const SessionsCompanion(isSynced: Value(true)));

  // ─── USERS ────────────────────────────────────────────────

  Future<User?> getUserByPin(String outletId, String hashedPin) =>
      (select(users)
            ..where(
              (u) =>
                  u.outletId.equals(outletId) &
                  u.pin.equals(hashedPin) &
                  u.isActive.equals(true),
            ))
          .getSingleOrNull();

  Future<List<User>> getUsers(String outletId) => (select(users)
        ..where(
          (u) => u.outletId.equals(outletId) & u.isActive.equals(true),
        )
        ..orderBy([(u) => OrderingTerm.asc(u.name)]))
      .get();

  Future<List<User>> getActiveUsers() => (select(users)
        ..where((u) => u.isActive.equals(true))
        ..orderBy([(u) => OrderingTerm.asc(u.name)]))
      .get();

  Future<User?> getActiveUserById(String userId) => (select(users)
        ..where((u) => u.id.equals(userId) & u.isActive.equals(true))
        ..limit(1))
      .getSingleOrNull();

  Future<List<String>> getUserOutletIds(String userId) async {
    final rows = await (select(userOutletAccesses)
          ..where((access) => access.userId.equals(userId)))
        .get();
    return rows.map((row) => row.outletId).toSet().toList();
  }

  Future<Map<String, List<String>>> getOutletIdsByUser() async {
    final rows = await select(userOutletAccesses).get();
    final map = <String, List<String>>{};
    for (final row in rows) {
      map.putIfAbsent(row.userId, () => []).add(row.outletId);
    }
    return map;
  }

  Future<void> replaceUserOutletAccess(
    String userId,
    Iterable<String> outletIds,
  ) async {
    final uniqueOutletIds = outletIds.toSet().toList();
    await transaction(() async {
      await (delete(userOutletAccesses)
            ..where((access) => access.userId.equals(userId)))
          .go();
      for (final outletId in uniqueOutletIds) {
        await into(userOutletAccesses).insert(
          UserOutletAccessesCompanion.insert(
            id: '${userId}_$outletId',
            userId: userId,
            outletId: outletId,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<List<User>> getUnsyncedUsers() =>
      (select(users)..where((u) => u.isSynced.equals(false))).get();

  Future<void> markUserSynced(String id) =>
      (update(users)..where((u) => u.id.equals(id)))
          .write(const UsersCompanion(isSynced: Value(true)));

  Future<List<UserOutletAccessesData>> getUnsyncedUserOutletAccesses() =>
      (select(userOutletAccesses)
            ..where((access) => access.isSynced.equals(false)))
          .get();

  Future<void> markUserOutletAccessSynced(String id) =>
      (update(userOutletAccesses)..where((access) => access.id.equals(id)))
          .write(const UserOutletAccessesCompanion(isSynced: Value(true)));

  Future<void> upsertUser(UsersCompanion user) =>
      into(users).insertOnConflictUpdate(user);

  Future<void> deactivateUser(String id) =>
      (update(users)..where((u) => u.id.equals(id)))
          .write(const UsersCompanion(isActive: Value(false)));
}

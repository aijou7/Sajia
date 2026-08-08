import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../core/database_encryption_service.dart';
import 'tables/app_tables.dart';
import 'daos/product_dao.dart';
import 'daos/order_dao.dart';
import 'daos/session_dao.dart';
import 'daos/sync_dao.dart';
import 'daos/finance_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    UserOutletAccesses,
    Outlets,
    Categories,
    Products,
    ProductVariants,
    RestaurantTables,
    Orders,
    OrderItems,
    Sessions,
    Expenses,
    SyncQueue,
  ],
  daos: [
    ProductDao,
    OrderDao,
    SessionDao,
    SyncDao,
    FinanceDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Untuk testing — inject in-memory db
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _insertDefaults();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(outlets, outlets.cloudExpiry);
          }
          if (from < 3) {
            await m.createTable(expenses);
          }
          if (from < 4) {
            await m.createTable(userOutletAccesses);
          }
          if (from < 5) {
            await m.addColumn(orderItems, orderItems.unitCogs);
            await m.addColumn(orderItems, orderItems.categoryId);
            await m.addColumn(orderItems, orderItems.categoryName);
          }
        },
        beforeOpen: (details) async {
          // Enable foreign keys
          await customStatement('PRAGMA foreign_keys = ON');
          // WAL mode untuk performa lebih baik
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// Seed data default saat pertama install
  Future<void> _insertDefaults() async {
    // Outlet default — akan diupdate saat setup
    return;
  }

  /// Whether this device still contains a configured business.
  Future<bool> hasBusinessData() async {
    final outlet = await (select(outlets)..limit(1)).getSingleOrNull();
    if (outlet != null) return true;
    final user = await (select(users)..limit(1)).getSingleOrNull();
    return user != null;
  }

  /// Keeps local rows only for the verified owner's outlets.
  ///
  /// Sajia uses one encrypted local database per installation. A change of
  /// Supabase owner must remove previous-account rows before PIN lookup or a
  /// recovery push can run.
  Future<void> retainOnlyOutlets(Set<String> allowedOutletIds) async {
    final localOutlets = await select(outlets).get();
    final removedOutletIds = localOutlets
        .map((outlet) => outlet.id)
        .where((id) => !allowedOutletIds.contains(id))
        .toSet();
    if (removedOutletIds.isEmpty) return;

    await transaction(() async {
      final removedOrders = await (select(orders)
            ..where((order) => order.outletId.isIn(removedOutletIds)))
          .get();
      final removedOrderIds = removedOrders.map((order) => order.id).toSet();
      if (removedOrderIds.isNotEmpty) {
        await (delete(orderItems)
              ..where((item) => item.orderId.isIn(removedOrderIds)))
            .go();
      }
      await (delete(orders)
            ..where((order) => order.outletId.isIn(removedOutletIds)))
          .go();

      final removedProducts = await (select(products)
            ..where((product) => product.outletId.isIn(removedOutletIds)))
          .get();
      final removedProductIds =
          removedProducts.map((product) => product.id).toSet();
      if (removedProductIds.isNotEmpty) {
        await (delete(productVariants)
              ..where((variant) => variant.productId.isIn(removedProductIds)))
            .go();
      }

      final removedUsers = await (select(users)
            ..where((user) => user.outletId.isIn(removedOutletIds)))
          .get();
      final removedUserIds = removedUsers.map((user) => user.id).toSet();
      await (delete(userOutletAccesses)
            ..where((access) => access.outletId.isIn(removedOutletIds)))
          .go();
      if (removedUserIds.isNotEmpty) {
        await (delete(userOutletAccesses)
              ..where((access) => access.userId.isIn(removedUserIds)))
            .go();
      }

      await (delete(sessions)
            ..where((session) => session.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(expenses)
            ..where((expense) => expense.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(restaurantTables)
            ..where((table) => table.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(products)
            ..where((product) => product.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(categories)
            ..where((category) => category.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(users)
            ..where((user) => user.outletId.isIn(removedOutletIds)))
          .go();
      await (delete(outlets)
            ..where((outlet) => outlet.id.isIn(removedOutletIds)))
          .go();

      // Legacy queue payloads are not all attributable to an outlet. Never
      // risk offering a previous owner's mutation to the new account.
      await delete(syncQueue).go();
    });
  }

  Future<void> clearBusinessData() => retainOnlyOutlets(const <String>{});
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'pos_fnb.db'));
    final databasePath = file.absolute.path;
    final databaseKey =
        await const DatabaseEncryptionService().getOrCreateKey();
    final escapedKey = DatabaseEncryptionService.escapeSqlString(databaseKey);

    return NativeDatabase.createInBackground(
      file,
      isolateSetup: () async {
        await migrateLegacyPlaintextDatabase(databasePath, escapedKey);
      },
      setup: (rawDb) {
        if (!_debugCheckHasCipher(rawDb)) {
          throw StateError('SQLite encryption backend tidak tersedia');
        }
        rawDb.execute("PRAGMA key = '$escapedKey';");
      },
    );
  });
}

bool _debugCheckHasCipher(sqlite.Database database) {
  return database.select('PRAGMA cipher;').isNotEmpty;
}

@visibleForTesting
Future<void> migrateLegacyPlaintextDatabase(
  String databasePath,
  String escapedKey,
) async {
  final databaseFile = File(databasePath);
  final tmp = File('${databaseFile.path}.encrypted.tmp');
  final backup = File('${databaseFile.path}.plaintext-migration-backup');
  final wal = File('${databaseFile.path}-wal');
  final shm = File('${databaseFile.path}-shm');

  // A process interruption between the two renames can leave the original
  // plaintext database only at [backup]. Restore it and retry the migration.
  if (!await databaseFile.exists() && await backup.exists()) {
    if (await tmp.exists()) await tmp.delete();
    await backup.rename(databaseFile.path);
  }

  if (!await databaseFile.exists()) {
    if (await tmp.exists()) await tmp.delete();
    return;
  }

  if (!await _isPlaintextSqliteDatabase(databaseFile)) {
    // A crash after installing the encrypted database but before deleting the
    // plaintext backup must not leave that reusable copy on disk forever.
    // Prove that the primary is readable with this device's key first.
    if (await backup.exists() || await tmp.exists()) {
      _verifyEncryptedDatabase(databaseFile, escapedKey);
      if (await tmp.exists()) await tmp.delete();
      if (await backup.exists()) await backup.delete();
    }
    return;
  }

  var primaryMovedToBackup = false;
  try {
    if (await tmp.exists()) await tmp.delete();
    if (await backup.exists()) await backup.delete();

    final plainDb = sqlite.sqlite3.open(databaseFile.path);
    try {
      if (!_debugCheckHasCipher(plainDb)) {
        throw StateError('SQLite encryption backend tidak tersedia');
      }
      plainDb.execute('PRAGMA wal_checkpoint(FULL);');
      plainDb.execute("VACUUM INTO '${_escapeSqlPath(tmp.path)}';");
    } finally {
      plainDb.close();
    }

    final tmpDb = sqlite.sqlite3.open(tmp.path);
    try {
      if (!_debugCheckHasCipher(tmpDb)) {
        throw StateError('SQLite encryption backend tidak tersedia');
      }
      tmpDb.execute("PRAGMA rekey = '$escapedKey';");
    } finally {
      tmpDb.close();
    }

    await databaseFile.rename(backup.path);
    primaryMovedToBackup = true;
    await tmp.rename(databaseFile.path);

    _verifyEncryptedDatabase(databaseFile, escapedKey);
    if (await wal.exists()) await wal.delete();
    if (await shm.exists()) await shm.delete();
    if (await backup.exists()) await backup.delete();
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    if (primaryMovedToBackup && await backup.exists()) {
      if (await databaseFile.exists()) await databaseFile.delete();
      await backup.rename(databaseFile.path);
    }
    rethrow;
  }
}

void _verifyEncryptedDatabase(File databaseFile, String escapedKey) {
  final encryptedDb = sqlite.sqlite3.open(databaseFile.path);
  try {
    if (!_debugCheckHasCipher(encryptedDb)) {
      throw StateError('SQLite encryption backend tidak tersedia');
    }
    encryptedDb.execute("PRAGMA key = '$escapedKey';");
    encryptedDb.select('SELECT count(*) FROM sqlite_master;');
  } finally {
    encryptedDb.close();
  }
}

Future<bool> _isPlaintextSqliteDatabase(File databaseFile) async {
  final length = await databaseFile.length();
  if (length < 16) return false;

  final header = await databaseFile.openRead(0, 16).first;
  return latin1.decode(header) == 'SQLite format 3\u0000';
}

String _escapeSqlPath(String path) {
  return path.replaceAll("'", "''");
}

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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
  int get schemaVersion => 4;

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
        await _encryptExistingPlaintextDatabase(databasePath, escapedKey);
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

Future<void> _encryptExistingPlaintextDatabase(
  String databasePath,
  String escapedKey,
) async {
  final databaseFile = File(databasePath);
  if (!await databaseFile.exists()) return;
  if (!await _isPlaintextSqliteDatabase(databaseFile)) return;

  final tmp = File('${databaseFile.path}.encrypted.tmp');
  final backup = File('${databaseFile.path}.plaintext-migration-backup');
  final wal = File('${databaseFile.path}-wal');
  final shm = File('${databaseFile.path}-shm');

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
    await tmp.rename(databaseFile.path);
    if (await wal.exists()) await wal.delete();
    if (await shm.exists()) await shm.delete();

    final encryptedDb = sqlite.sqlite3.open(databaseFile.path);
    try {
      encryptedDb.execute("PRAGMA key = '$escapedKey';");
      encryptedDb.select('SELECT count(*) FROM sqlite_master;');
    } finally {
      encryptedDb.close();
    }

    if (await backup.exists()) await backup.delete();
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    if (!await databaseFile.exists() && await backup.exists()) {
      await backup.rename(databaseFile.path);
    }
    rethrow;
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  const databaseKey = 'migration-test-key';

  late Directory tempDirectory;
  late File databaseFile;
  late File backupFile;
  late File temporaryFile;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('sajia-db-migration-');
    databaseFile = File('${tempDirectory.path}${Platform.pathSeparator}pos.db');
    backupFile = File('${databaseFile.path}.plaintext-migration-backup');
    temporaryFile = File('${databaseFile.path}.encrypted.tmp');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('removes plaintext backup after verifying encrypted primary', () async {
    _createEncryptedDatabase(databaseFile, databaseKey, 'encrypted-primary');
    _createPlaintextDatabase(backupFile, 'plaintext-backup');
    _createEncryptedDatabase(temporaryFile, databaseKey, 'stale-temporary');

    await migrateLegacyPlaintextDatabase(databaseFile.path, databaseKey);

    expect(await backupFile.exists(), isFalse);
    expect(await temporaryFile.exists(), isFalse);
    expect(
      _readEncryptedValue(databaseFile, databaseKey),
      'encrypted-primary',
    );
  });

  test('restores and retries when interruption left no primary', () async {
    _createPlaintextDatabase(backupFile, 'recovered-plaintext');
    _createEncryptedDatabase(temporaryFile, databaseKey, 'stale-temporary');

    await migrateLegacyPlaintextDatabase(databaseFile.path, databaseKey);

    expect(await databaseFile.exists(), isTrue);
    expect(await backupFile.exists(), isFalse);
    expect(await temporaryFile.exists(), isFalse);
    expect(
      _readEncryptedValue(databaseFile, databaseKey),
      'recovered-plaintext',
    );
  });

  test('keeps plaintext backup when the primary cannot be verified', () async {
    _createEncryptedDatabase(databaseFile, databaseKey, 'encrypted-primary');
    _createPlaintextDatabase(backupFile, 'plaintext-backup');

    expect(
      () => migrateLegacyPlaintextDatabase(databaseFile.path, 'wrong-key'),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(await backupFile.exists(), isTrue);
  });
}

void _createPlaintextDatabase(File file, String value) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('CREATE TABLE secrets (value TEXT NOT NULL);');
    database.execute('INSERT INTO secrets (value) VALUES (?);', [value]);
  } finally {
    database.close();
  }
}

void _createEncryptedDatabase(File file, String key, String value) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute("PRAGMA key = '$key';");
    database.execute('CREATE TABLE secrets (value TEXT NOT NULL);');
    database.execute('INSERT INTO secrets (value) VALUES (?);', [value]);
  } finally {
    database.close();
  }
}

String _readEncryptedValue(File file, String key) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute("PRAGMA key = '$key';");
    return database.select('SELECT value FROM secrets;').single['value']
        as String;
  } finally {
    database.close();
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseEncryptionService {
  static const _keyName = 'sajia.local_database.encryption_key.v1';
  static const _storage = FlutterSecureStorage();

  const DatabaseEncryptionService();

  Future<String> getOrCreateKey() async {
    final stored = await _storage.read(key: _keyName);
    if (stored != null && stored.length >= 32) return stored;

    final bytes = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
      growable: false,
    );
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _keyName, value: key);
    return key;
  }

  static String escapeSqlString(String source) {
    return source.replaceAll("'", "''");
  }
}

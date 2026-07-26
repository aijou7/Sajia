import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('sqlite native backend supports encryption pragmas', () {
    final db = sqlite3.openInMemory();
    try {
      final cipherRows = db.select('PRAGMA cipher;');
      expect(cipherRows, isNotEmpty);
    } finally {
      db.close();
    }
  });
}

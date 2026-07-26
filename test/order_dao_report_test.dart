import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  test('empty sales summary keeps monetary values as doubles', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final date = DateTime(2026, 7, 26);
    final summary = await database.orderDao.getSalesSummaryForScope(
      null,
      DateTime(date.year, date.month, date.day),
      DateTime(date.year, date.month, date.day, 23, 59, 59),
    );

    expect(summary['orderCount'], 0);
    expect(summary['totalRevenue'], 0.0);
    expect(summary['totalCash'], 0.0);
    expect(summary['totalQris'], 0.0);
    expect(summary['avgOrderValue'], 0.0);
    expect(summary['avgOrderValue'], isA<double>());
  });
}

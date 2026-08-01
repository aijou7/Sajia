import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  test('branch summaries hide the legacy placeholder when a real outlet exists',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.into(database.outlets).insert(
          OutletsCompanion.insert(
            id: 'default-outlet',
            name: 'Nama Kafe Saya',
            licenseKey: 'FREE',
          ),
        );
    await database.into(database.outlets).insert(
          OutletsCompanion.insert(
            id: 'real-outlet',
            name: 'Kafe Nyata',
            licenseKey: 'FREE',
          ),
        );

    final summaries = await database.financeDao.getBranchSummaries(
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 1, 23, 59, 59),
    );

    expect(summaries.map((summary) => summary.outletName), ['Kafe Nyata']);
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/features/menu/menu_page.dart';

Future<void> _showProductForm(
  WidgetTester tester, {
  required bool cloud,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  await database.into(database.outlets).insert(
        OutletsCompanion.insert(
          id: 'default-outlet',
          name: 'Kafe',
          licenseKey: cloud ? 'PRO' : 'FREE',
          cloudExpiry: cloud ? Value(DateTime(2027, 1, 1)) : const Value(null),
        ),
      );
  await database.productDao.upsertProduct(
    ProductsCompanion.insert(
      id: 'coffee',
      outletId: 'default-outlet',
      name: 'Kopi Susu',
      price: '20000',
      cogs: const Value('5000'),
    ),
  );
  final product = await database.productDao.getProduct('coffee');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        home: Scaffold(body: ProductFormSheet(product: product)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cloud menu shows HPP as dashboard-managed, not editable',
      (tester) async {
    await _showProductForm(tester, cloud: true);

    expect(find.textContaining('atur resep dan buffer di Dashboard Owner'),
        findsOneWidget);
    expect(find.text('Biaya menu (opsional)'), findsNothing);
    expect(find.text('HPP manual'), findsNothing);
  });

  testWidgets('offline menu keeps costing under an optional section',
      (tester) async {
    await _showProductForm(tester, cloud: false);

    expect(find.text('Biaya menu (opsional)'), findsOneWidget);
    expect(find.textContaining('atur resep dan buffer di Dashboard Owner'),
        findsNothing);
    await tester.ensureVisible(find.text('Biaya menu (opsional)'));
    await tester.tap(find.text('Biaya menu (opsional)'));
    await tester.pumpAndSettle();
    expect(find.text('HPP manual'), findsOneWidget);
    expect(find.text('Hitung HPP'), findsOneWidget);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/features/cashier/payment_sheet.dart';

void main() {
  testWidgets('checkout is blocked until outlet pricing is loaded',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(
          home: Scaffold(body: PaymentSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QRIS Manual'), findsOneWidget);
    expect(
      find.textContaining('Pembayaran belum dapat dikonfirmasi'),
      findsOneWidget,
    );

    final submit = find.descendant(
      of: find.byKey(const ValueKey('payment-submit')),
      matching: find.byType(InkWell),
    );
    expect(submit, findsOneWidget);
    expect(tester.widget<InkWell>(submit).onTap, isNull);
  });
}

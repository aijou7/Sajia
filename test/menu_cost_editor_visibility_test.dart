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
  final outlet = Outlet(
    id: 'default-outlet',
    name: 'Kafe',
    taxPercent: '0',
    serviceChargePercent: '0',
    licenseKey: cloud ? 'PRO' : 'FREE',
    cloudExpiry: cloud ? DateTime(2027, 1, 1) : null,
    createdAt: DateTime(2026, 1, 1),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentOutletProvider.overrideWith((ref) async => outlet),
        categoriesProvider.overrideWith((ref) => Stream.value(<Category>[])),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ProductFormSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cloud menu directs HPP editing to dashboard', (tester) async {
    await _showProductForm(tester, cloud: true);

    expect(find.textContaining('diatur dari Dashboard Owner'), findsOneWidget);
    expect(find.text('Biaya menu (opsional)'), findsNothing);
    expect(find.text('HPP manual'), findsNothing);
  });

  testWidgets('offline menu keeps costing under an optional section',
      (tester) async {
    await _showProductForm(tester, cloud: false);

    expect(find.text('Biaya menu (opsional)'), findsOneWidget);
    expect(find.textContaining('diatur dari Dashboard Owner'), findsNothing);
    await tester.ensureVisible(find.text('Biaya menu (opsional)'));
    await tester.tap(find.text('Biaya menu (opsional)'));
    await tester.pumpAndSettle();
    expect(find.text('HPP manual'), findsOneWidget);
    expect(find.text('Hitung HPP'), findsOneWidget);
  });
}

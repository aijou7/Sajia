import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/features/shared/startup_splash.dart';

void main() {
  testWidgets('startup splash shows animated Sajia loading state',
      (tester) async {
    await tester.pumpWidget(const SajiaStartupSplash());

    expect(find.text('Sajia'), findsOneWidget);
    expect(find.text('KASIR & OPERASIONAL F&B'), findsOneWidget);
    expect(find.text('Menyiapkan Sajia'), findsOneWidget);
    expect(find.bySemanticsLabel('Sajia sedang disiapkan'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup error offers a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      SajiaStartupError(onRetry: () => retried = true),
    );

    expect(find.text('Sajia belum dapat disiapkan'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));

    expect(retried, isTrue);
  });
}

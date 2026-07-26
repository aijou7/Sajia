import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_mobile/main.dart';

void main() {
  testWidgets('shows onboarding when setup is not done', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done': false});

    await tester.pumpWidget(
      const ProviderScope(
        child: SajiaApp(startSyncOnLaunch: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Selamat Datang'), findsOneWidget);
  });
}

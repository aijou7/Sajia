import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_mobile/core/app_notice.dart';
import 'package:pos_mobile/core/onboarding_service.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/core/theme.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/sync_service.dart';
import 'package:pos_mobile/domain/entities/entities.dart';
import 'package:pos_mobile/features/settings/settings_page.dart';
import 'package:pos_mobile/features/shared/main_scaffold.dart';

class _Owner extends CurrentUserNotifier {
  @override
  AppUser build() => const AppUser(
      id: 'owner', name: 'Owner', role: 'owner', outletId: 'local');
}

class _Sync extends SyncService {
  _Sync(super.database, super.client);
  int retries = 0;
  int attempts = 0;
  SyncStatus snapshot = const SyncStatus(
    phase: SyncPhase.deferred,
    pendingCount: 11,
    errorMessage:
        'Penjualan belum dikirim. Pastikan Cloud aktif pada outlet yang sama.',
  );

  @override
  SyncStatus get status => snapshot;

  @override
  Future<void> syncAll() async {
    attempts++;
  }

  @override
  void requestSync() {
    retries++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SupabaseClient client;
  late _Sync sync;

  setUpAll(() async {
    final fonts = FontLoader('Inter');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black'
    ]) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Kasata',
      packageName: 'id.aksaldev.sajia',
      version: '1.0.31',
      buildNumber: '2034',
      buildSignature: '',
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.outlets).insert(OutletsCompanion.insert(
          id: 'local',
          name: 'Cafe',
          licenseKey: 'PRO',
          cloudExpiry: Value(DateTime.utc(2099)),
        ));
    await db.into(db.orders).insert(OrdersCompanion.insert(
          id: 'sale',
          outletId: 'local',
          orderNumber: '001',
          type: 'takeaway',
          status: 'paid',
          cashierId: 'owner',
          cashierName: 'Owner',
          total: const Value('331420'),
        ));
    await OnboardingService().bindVerifiedAccount(
      authUserId: 'owner',
      email: 'owner@example.test',
      outletIds: ['local'],
    );
    await OnboardingService().markSetupDone();
    client = SupabaseClient('https://ui-test.supabase.co', 'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    sync = _Sync(db, client);
  });

  tearDown(() async {
    AppNotice.dismiss();
    sync.dispose();
    await client.dispose();
    await db.close();
  });

  Widget scope(Widget child) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          supabaseProvider.overrideWithValue(client),
          syncServiceProvider.overrideWithValue(sync),
          currentUserProvider.overrideWith(_Owner.new),
          currentOutletProvider.overrideWith(
              (ref) async => (await db.select(db.outlets).get()).single),
          syncStatusProvider.overrideWith((ref) => Stream.value(sync.status)),
        ],
        child: child,
      );

  for (final scenario in [
    (name: 'phone', size: const Size(390, 844), scale: 1.3),
    (name: 'tablet', size: const Size(800, 600), scale: 1.0),
  ]) {
    testWidgets(
        'pending sales status and retry are readable on ${scenario.name}',
        (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      await tester.pumpWidget(scope(RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: const MainScaffold(currentIndex: 7),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('11'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Status sinkronisasi'), findsOneWidget);
      expect(find.textContaining('Penjualan belum dikirim'), findsOneWidget);
      expect(find.textContaining('11 perubahan menunggu'), findsOneWidget);
      expect(find.textContaining('terakhir berhasil'), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('KASATA_VISUAL_REVIEW')) {
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 1);
          final bytes =
              await rendered.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/visual-review').create(recursive: true);
          await File('build/visual-review/pending-sync-${scenario.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(sync.retries, 1);
      expect(find.text('Status sinkronisasi'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('settings shows a warning when sync leaves sales pending',
      (tester) async {
    await tester.pumpWidget(
        scope(MaterialApp(theme: AppTheme.light, home: const SettingsPage())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sinkronisasi Data'), 400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinkronisasi Data'));
    await tester.pumpAndSettle();
    expect(sync.attempts, 1);
    expect(find.text(sync.status.errorMessage!), findsOneWidget);
    expect(find.text('Sinkronisasi selesai'), findsNothing);
    expect(tester.takeException(), isNull);
    AppNotice.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmed email logout keeps local sales and ownership',
      (tester) async {
    final router = GoRouter(initialLocation: '/settings', routes: [
      GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
      GoRoute(
          path: '/onboarding',
          builder: (_, __) => const Scaffold(body: Text('Login email'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        scope(MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Logout akun email'), 400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout akun email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout akun'));
    await tester.pumpAndSettle();
    expect(find.text('Login email'), findsOneWidget);
    final sale = (await db.select(db.orders).get()).single;
    expect(sale.total, '331420');
    expect(sale.isSynced, isFalse);
    expect(await OnboardingService().getVerifiedAuthUserId(), 'owner');
    expect(await OnboardingService().getVerifiedOwnerOutletIds(), {'local'});
    expect(await OnboardingService().isSetupDone(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

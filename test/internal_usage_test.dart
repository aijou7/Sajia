import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/sync_service.dart';
import 'package:pos_mobile/domain/entities/entities.dart';
import 'package:pos_mobile/domain/ingredient_inventory.dart';
import 'package:pos_mobile/features/cashier/internal_usage.dart';
import 'package:pos_mobile/features/cashier/cart_panel.dart';
import 'package:pos_mobile/core/providers.dart';
import 'package:pos_mobile/core/app_notice.dart';

class _UsageOwner extends CurrentUserNotifier {
  @override
  AppUser build() =>
      const AppUser(id: 'owner', name: 'Owner', role: 'owner', outletId: 'a');
}

class _UsageCart extends CartNotifier {
  @override
  Cart build() => const Cart(items: [
        CartItem(
            productId: 'coffee',
            productName: 'Kopi',
            unitPrice: 20000,
            unitCogs: 5000)
      ]);
}

class _UsageOutlet extends CurrentOutletIdNotifier {
  @override
  String build() => 'a';
}

class _UsageSync extends SyncService {
  _UsageSync(super.db, super.client);
  int requests = 0;
  @override
  void requestSync() {
    requests++;
  }
}

// The cashier only requests a sync here. Actual authenticated HTTP retries are
// exercised independently in ingredient_sync_test.dart.
class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf')))
        .load();
  });
  test('variants consume one recipe quantity and internal use creates no sale',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.productDao.upsertProduct(ProductsCompanion.insert(
        id: 'coffee',
        outletId: 'a',
        name: 'Kopi',
        price: '20000',
        trackStock: const Value(true),
        stock: const Value('10')));
    const cart = Cart(items: [
      CartItem(
          productId: 'coffee',
          productName: 'Kopi',
          unitPrice: 20000,
          unitCogs: 5000),
      CartItem(
          productId: 'coffee',
          productName: 'Kopi',
          unitPrice: 22000,
          unitCogs: 5000,
          variantSummary: 'Extra ice')
    ]);
    await enqueueInternalUsage(
        db: db, cart: cart, outletId: 'a', purpose: 'rnd', id: 'usage-1');
    expect((await db.productDao.getProduct('coffee'))!.stock, '8.0');
    expect(await db.select(db.orders).get(), isEmpty);
    expect(await db.select(db.orderItems).get(), isEmpty);
    expect(await db.select(db.expenses).get(), isEmpty);
    final queue = await db.syncDao.getPending();
    expect(queue.single.recordId, 'usage-1');
    final payload = jsonDecode(queue.single.payload) as Map;
    expect(payload['items'], [
      {'product_id': 'coffee', 'quantity': 2.0}
    ]);
    expect(payload['purpose'], 'rnd');
    for (var retry = 0; retry < 6; retry++) {
      await db.syncDao.incrementRetry(queue.single.id, 'offline');
    }
    expect(await db.syncDao.getPendingCount(), 1,
        reason: 'financial usage must not vanish after five attempts');
  });
  test('a failed internal use rolls back every stock decrement and its queue',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.productDao.upsertProduct(ProductsCompanion.insert(
        id: 'a',
        outletId: 'outlet',
        name: 'A',
        price: '10',
        trackStock: const Value(true),
        stock: const Value('10')));
    await db.productDao.upsertProduct(ProductsCompanion.insert(
        id: 'b', outletId: 'other', name: 'B', price: '10'));
    const cart = Cart(items: [
      CartItem(productId: 'a', productName: 'A', unitPrice: 10),
      CartItem(productId: 'b', productName: 'B', unitPrice: 10)
    ]);
    await expectLater(
        enqueueInternalUsage(
            db: db, cart: cart, outletId: 'outlet', purpose: 'personal'),
        throwsStateError);
    expect((await db.productDao.getProduct('a'))!.stock, '10');
    expect(await db.syncDao.getPendingCount(), 0);
  });
  test('usage rejects nonfinite or negative amounts', () {
    expect(() => aggregateUsageItems([(productId: 'a', quantity: double.nan)]),
        throwsArgumentError);
    expect(() => aggregateUsageItems([(productId: 'a', quantity: -1)]),
        throwsArgumentError);
  });
  testWidgets(
      'cashier internal use blocks duplicate taps and creates no payment',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    await db.into(db.outlets).insert(OutletsCompanion.insert(
        id: 'a',
        name: 'A',
        licenseKey: 'PRO',
        cloudExpiry: Value(DateTime(2099))));
    await db.productDao.upsertProduct(ProductsCompanion.insert(
        id: 'coffee',
        outletId: 'a',
        name: 'Kopi',
        price: '20000',
        trackStock: const Value(true),
        stock: const Value('10')));
    final sync = _UsageSync(db, _UnusedClient());
    addTearDown(sync.dispose);
    final outlet = await db.select(db.outlets).getSingle();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith(_UsageOwner.new),
          currentOutletIdProvider.overrideWith(_UsageOutlet.new),
          currentOutletProvider.overrideWith((ref) async => outlet),
          tablesProvider.overrideWith((ref) => Stream.value([])),
          cartProvider.overrideWith(_UsageCart.new),
          syncServiceProvider.overrideWithValue(sync),
        ],
        child: MaterialApp(
            theme: ThemeData(fontFamily: 'Inter'),
            home: Scaffold(
                body: CartPanel(
                    onCheckout: () => fail('Internal use cannot checkout'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atur diskon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('R&D / Kalibrasi · HPP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat pemakaian'));
    await tester.tap(find.text('Catat pemakaian'));
    await tester.pumpAndSettle();
    final queue = await db.syncDao.getPending();
    expect(queue.length, 1);
    expect((await db.productDao.getProduct('coffee'))!.stock, '9.0');
    expect(sync.requests, 1);
    expect(await db.select(db.orders).get(), isEmpty);
    expect(find.text('Belum ada pesanan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    AppNotice.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

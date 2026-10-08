import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pos_mobile/core/onboarding_service.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/sync_service.dart';

const _ownerId = '00000000-0000-0000-0000-000000000001';

class _Cloud {
  bool active = false;
  bool failScope = false;
  bool failPlan = false;
  bool failOrders = false;
  Set<String> outletIds = {'local'};
  final inactiveOutlets = <String>{};
  final orders = <String, Map<String, dynamic>>{};
  final items = <String, Map<String, dynamic>>{};
  final sessions = <String, Map<String, dynamic>>{};
  final expenses = <String, Map<String, dynamic>>{};
  Future<void> Function(String, Map<String, dynamic>)? duringUpload;
  final writes = <String>[];
  Completer<void>? scopeStarted;
  Completer<void>? scopeRelease;

  Future<http.Response> handle(http.Request request) async {
    final endpoint = request.url.pathSegments.last;
    Object data = [];
    var status = 200;
    if (request.url.path.contains('/auth/')) {
      final token = '${base64Url.encode(utf8.encode('{}'))}.'
          '${base64Url.encode(utf8.encode('{"exp":4102444800}'))}.test';
      data = {
        'access_token': token,
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 86400,
        'user': {
          'id': _ownerId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'owner@example.test',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
    } else if (endpoint == 'get_authenticated_owner_outlets') {
      if (scopeStarted != null && !scopeStarted!.isCompleted) {
        scopeStarted!.complete();
      }
      await scopeRelease?.future;
      if (failScope) {
        status = 503;
        data = {'code': 'TEST_OFFLINE', 'message': 'scope unavailable'};
      } else {
        data = outletIds
            .map((id) => {'id': id, 'name': 'Cafe', 'license_key': 'PRO'})
            .toList();
      }
    } else if (endpoint == 'get-plan-status') {
      if (failPlan) {
        status = 503;
        data = {'error': 'test plan unavailable'};
      } else {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final enabled = active && !inactiveOutlets.contains(body['outlet_id']);
        data = {
          'is_pro': true,
          'is_cloud': enabled,
          'expires_at': enabled ? '2099-01-01T00:00:00Z' : null
        };
      }
    } else if (['orders', 'order_items', 'sessions', 'expenses']
        .contains(endpoint)) {
      final rows = switch (endpoint) {
        'orders' => orders,
        'order_items' => items,
        'sessions' => sessions,
        _ => expenses,
      };
      if (request.method == 'GET') {
        data = rows.values.toList();
      } else if (failOrders && endpoint == 'orders') {
        status = 503;
        data = {'code': 'TEST_OFFLINE', 'message': 'upload failed'};
      } else {
        writes.add(endpoint);
        final row = jsonDecode(request.body) as Map<String, dynamic>;
        await duringUpload?.call(endpoint, row);
        rows[row['id'] as String] = row;
      }
    } else if (request.method != 'GET' && !request.url.path.contains('/rpc/')) {
      writes.add(endpoint);
      if (endpoint == 'outlets') {
        outletIds.add((jsonDecode(request.body) as Map)['id'] as String);
      }
    }
    return http.Response(jsonEncode(data), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  late AppDatabase db;
  late _Cloud cloud;
  late SupabaseClient client;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => ['wifi']);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.outlets).insert(
        OutletsCompanion.insert(id: 'local', name: 'Cafe', licenseKey: 'PRO'));
    for (var i = 0; i < 11; i++) {
      await db.into(db.orders).insert(OrdersCompanion.insert(
            id: 'sale-$i',
            outletId: 'local',
            orderNumber: 'SALE-$i',
            type: 'takeaway',
            status: 'paid',
            cashierId: 'owner',
            cashierName: 'Owner',
            total: Value(i == 0 ? '31420' : '30000'),
            paidAt: Value(DateTime.utc(2026, 10, 6)),
          ));
    }
    cloud = _Cloud();
    client = SupabaseClient('https://sync-test.supabase.co', 'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(cloud.handle));
    await client.auth
        .signInWithPassword(email: 'owner@example.test', password: 'test-only');
    await OnboardingService().bindVerifiedAccount(
        authUserId: _ownerId,
        email: 'owner@example.test',
        outletIds: ['local']);
    sync = SyncService(db, client);
  });

  tearDown(() async {
    sync.dispose();
    await client.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> expectLocalSales({bool unsynced = true}) async {
    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(11));
    expect(rows.fold<double>(0, (sum, row) => sum + double.parse(row.total)),
        331420);
    expect(rows.every((row) => row.isSynced == !unsynced), isTrue);
  }

  test(
      'expired Cloud preserves 11 local sales; renewal uploads the old backlog',
      () async {
    await sync.syncAll();
    await expectLocalSales();
    expect(cloud.orders, isEmpty);
    expect(sync.status.phase, SyncPhase.deferred);
    expect(sync.status.pendingCount, 11);
    cloud.active = true;
    await sync.syncAll();
    await expectLocalSales(unsynced: false);
    expect(cloud.orders, hasLength(11));
    expect(sync.status.phase, SyncPhase.synced);
    expect(sync.status.pendingCount, 0);
    await sync.syncAll();
    expect(cloud.orders, hasLength(11));
    expect(
        cloud.writes.where((endpoint) => endpoint == 'orders'), hasLength(11));
  });

  test(
      'remote outlet mismatch stops before writes and never deletes local sales',
      () async {
    cloud.outletIds = {'another-outlet'};
    await sync.syncAll();
    expect(sync.status.phase, SyncPhase.failed);
    expect(sync.status.errorMessage, contains('Data tidak dihapus'));
    expect(cloud.writes, isEmpty);
    await expectLocalSales();
  });

  test('scope lookup failure cannot fall back to uploading local data',
      () async {
    cloud.failScope = true;
    await sync.syncAll();
    expect(sync.status.phase, SyncPhase.failed);
    expect(cloud.writes, isEmpty);
    await expectLocalSales();
  });

  test('another authenticated account cannot upload or delete the bound data',
      () async {
    await OnboardingService().bindVerifiedAccount(
        authUserId: 'other-owner',
        email: 'other@example.test',
        outletIds: ['local']);
    await sync.syncAll();
    expect(sync.status.phase, SyncPhase.failed);
    expect(cloud.writes, isEmpty);
    await expectLocalSales();
  });

  test('Cloud status lookup failure is reported, not success', () async {
    cloud.failPlan = true;
    await sync.syncAll();
    expect(sync.status.phase, SyncPhase.failed);
    expect(sync.status.pendingCount, 11);
    expect(sync.status.errorMessage, contains('Status Cloud'));
    await expectLocalSales();
  });

  test('a bound first-time outlet may register when the server scope is empty',
      () async {
    cloud.outletIds.clear();
    cloud.active = true;
    await sync.pauseForAccountChange();
    await sync.syncAll();
    expect(cloud.writes, isEmpty);
    sync.resumeAfterAccountChange();
    await sync.syncAll();
    await expectLocalSales(unsynced: false);
    expect(cloud.orders, hasLength(11));
    expect(sync.status.phase, SyncPhase.synced);
  });

  test('a backlog on a non-entitled branch cannot report complete success',
      () async {
    cloud.active = true;
    cloud.outletIds.add('branch');
    cloud.inactiveOutlets.add('branch');
    await db.into(db.outlets).insert(OutletsCompanion.insert(
          id: 'branch',
          name: 'Branch',
          licenseKey: 'FREE',
        ));
    await db.into(db.orders).insert(OrdersCompanion.insert(
          id: 'branch-sale',
          outletId: 'branch',
          orderNumber: 'BRANCH-1',
          type: 'takeaway',
          status: 'paid',
          cashierId: 'owner',
          cashierName: 'Owner',
          total: const Value('18000'),
        ));
    await sync.syncAll();
    expect(cloud.orders, hasLength(11));
    final branch = await (db.select(db.orders)
          ..where((row) => row.id.equals('branch-sale')))
        .getSingle();
    expect(branch.total, '18000');
    expect(branch.isSynced, isFalse);
    expect(sync.status.phase, SyncPhase.deferred);
    expect(sync.status.pendingCount, 1);
    expect(sync.status.errorMessage, contains('belum terkirim'));
  });

  test('failed transaction upload preserves its retry flag and reports failure',
      () async {
    cloud.active = true;
    cloud.failOrders = true;
    await sync.syncAll();
    expect(sync.status.phase, SyncPhase.failed);
    expect(sync.status.pendingCount, 11);
    await expectLocalSales();
  });

  test(
      'same-owner login pull cannot overwrite an unsynced paid sale or HPP item',
      () async {
    cloud.active = true;
    cloud.orders['sale-0'] = {
      'id': 'sale-0',
      'outlet_id': 'local',
      'order_number': 'SALE-0',
      'status': 'unpaid',
      'total': '0',
    };
    await db.into(db.orderItems).insert(OrderItemsCompanion.insert(
          id: 'item-0',
          orderId: 'sale-0',
          productId: 'coffee',
          productName: 'Kopi',
          unitPrice: '31420',
          unitCogs: const Value('6856'),
          quantity: '1',
          subtotal: '31420',
        ));
    cloud.items['item-0'] = {
      'id': 'item-0',
      'order_id': 'sale-0',
      'product_id': 'coffee',
      'product_name': 'Kopi',
      'unit_price': '0',
      'quantity': '1',
      'subtotal': '0',
    };
    await sync.pauseForAccountChange();
    expect(await sync.pullAllForLogin('local'), isTrue);
    await expectLocalSales();
    final item = (await db.select(db.orderItems).get()).single;
    expect(item.unitCogs, '6856');
    expect(item.subtotal, '31420');
    expect(item.isSynced, isFalse);
  });

  test(
      'account change drains the worker and suppresses subsequent background sync',
      () async {
    cloud.scopeStarted = Completer<void>();
    cloud.scopeRelease = Completer<void>();
    final running = sync.syncAll();
    await cloud.scopeStarted!.future;
    var paused = false;
    final pausing = sync.pauseForAccountChange().then((_) => paused = true);
    await Future<void>.delayed(Duration.zero);
    expect(paused, isFalse);
    cloud.scopeRelease!.complete();
    await running;
    await pausing;
    final writesBefore = cloud.writes.length;
    await sync.syncAll();
    expect(cloud.writes, hasLength(writesBefore));
    sync.resumeAfterAccountChange();
    cloud.active = true;
    await sync.syncAll();
    expect(cloud.orders, hasLength(11));
  });

  test('a second manual sync waits for the worker instead of reporting early',
      () async {
    cloud.active = true;
    cloud.scopeStarted = Completer<void>();
    cloud.scopeRelease = Completer<void>();
    final running = sync.syncAll();
    await cloud.scopeStarted!.future;
    var finished = false;
    final joined = sync.syncAll().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    cloud.scopeRelease!.complete();
    await running;
    await joined;
    expect(finished, isTrue);
    expect(cloud.orders, hasLength(11));
    expect(cloud.writes.where((table) => table == 'orders'), hasLength(11));
    expect(sync.status.phase, SyncPhase.synced);
  });

  test('edits during upload remain pending and survive the old cloud snapshot',
      () async {
    cloud.active = true;
    await db.into(db.orderItems).insert(OrderItemsCompanion.insert(
          id: 'item-0',
          orderId: 'sale-0',
          productId: 'coffee',
          productName: 'Kopi',
          unitPrice: '20000',
          quantity: '1',
          subtotal: '20000',
        ));
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: 'shift-0',
          outletId: 'local',
          cashierId: 'owner',
          cashierName: 'Owner',
        ));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'expense-0',
          outletId: 'local',
          category: 'Operasional',
          amount: '10000',
          occurredAt: DateTime.utc(2026, 10, 6),
        ));
    final edited = <String>{};
    cloud.duringUpload = (table, row) async {
      if (!edited.add(table)) return;
      switch (table) {
        case 'orders':
          await (db.update(db.orders)..where((r) => r.id.equals('sale-0')))
              .write(
            const OrdersCompanion(
                total: Value('32000'), isSynced: Value(false)),
          );
        case 'order_items':
          await (db.update(db.orderItems)..where((r) => r.id.equals('item-0')))
              .write(
            const OrderItemsCompanion(
                quantity: Value('2'),
                subtotal: Value('40000'),
                isSynced: Value(false)),
          );
        case 'sessions':
          await (db.update(db.sessions)..where((r) => r.id.equals('shift-0')))
              .write(
            const SessionsCompanion(
                totalOrders: Value(2),
                totalCashSales: Value('40000'),
                isSynced: Value(false)),
          );
        case 'expenses':
          await (db.update(db.expenses)..where((r) => r.id.equals('expense-0')))
              .write(
            const ExpensesCompanion(
                amount: Value('20000'), isSynced: Value(false)),
          );
      }
    };

    await sync.syncAll();
    expect(cloud.orders['sale-0']!['total'], '31420');
    expect((await db.orderDao.getOrder('sale-0'))!.total, '32000');
    expect((await db.select(db.orderItems).get()).single.subtotal, '40000');
    expect((await db.select(db.sessions).get()).single.totalCashSales, '40000');
    expect((await db.select(db.expenses).get()).single.amount, '20000');
    expect(await db.pendingFinancialChanges(), 4);
    expect(sync.status.phase, SyncPhase.deferred);

    await sync.syncAll();
    expect(cloud.orders, hasLength(11));
    expect(cloud.orders['sale-0']!['total'], '32000');
    expect(cloud.items['item-0']!['subtotal'], '40000');
    expect(cloud.sessions['shift-0']!['total_cash_sales'], '40000');
    expect(cloud.expenses['expense-0']!['amount'], '20000');
    expect(await db.pendingFinancialChanges(), 0);
    expect(sync.status.phase, SyncPhase.synced);
  });
}

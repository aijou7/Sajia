import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_mobile/core/onboarding_service.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/sync_service.dart';
import 'package:pos_mobile/domain/entities/entities.dart';
import 'package:pos_mobile/features/cashier/internal_usage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => ['wifi']);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final missingProfiles in [false, true]) {
    test(
        missingProfiles
            ? 'menu upload is not blocked by a missing costing profile migration'
            : 'offline internal usage survives pulls and retries beyond five attempts',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.outlets).insert(
          OutletsCompanion.insert(id: 'a', name: 'A', licenseKey: 'PRO'));
      await db.productDao.upsertProduct(ProductsCompanion.insert(
          id: 'coffee',
          outletId: 'a',
          name: 'Kopi',
          price: '20000',
          trackStock: const Value(true),
          stock: const Value('10')));
      var failUsage = true;
      var remoteStock = '10';
      var productUploads = 0;
      final calls = <Map<String, dynamic>>[];
      final outlet = {'id': 'a', 'name': 'A', 'license_key': 'PRO'};
      final client = SupabaseClient('https://sync-test.supabase.co', 'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
        Object data = [];
        var status = 200;
        final endpoint = request.url.pathSegments.last;
        if (request.url.path.contains('/auth/')) {
          final token =
              '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({
                'exp': 4102444800
              })))}.test';
          data = {
            'access_token': token,
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 86400,
            'user': {
              'id': '00000000-0000-0000-0000-000000000001',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'owner@example.test',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z'
            }
          };
        } else if (endpoint == 'get_authenticated_owner_outlets') {
          data = [outlet];
        } else if (endpoint == 'get-plan-status') {
          data = {
            'is_pro': true,
            'is_cloud': true,
            'expires_at': '2099-01-01T00:00:00Z'
          };
        } else if (endpoint == 'products') {
          if (request.method == 'GET') {
            final product = {
              'id': 'coffee',
              'outlet_id': 'a',
              'name': 'Kopi',
              'price': '20000',
              'cogs': '5000',
              'stock': remoteStock,
              'track_stock': true
            };
            data = request.headers['accept']?.contains('object') == true
                ? product
                : [product];
          } else {
            productUploads++;
          }
        } else if (endpoint == 'product_cost_profiles' && missingProfiles) {
          status = 404;
          data = {'code': 'PGRST205', 'message': 'test missing migration'};
        } else if (endpoint == 'record_internal_material_usage') {
          calls.add(jsonDecode(request.body) as Map<String, dynamic>);
          expect((await db.productDao.getProduct('coffee'))!.stock, '9.0');
          if (failUsage) {
            status = 503;
            data = {
              'code': 'TEST_OFFLINE',
              'message': 'test connection failure'
            };
          } else {
            remoteStock = '9.0';
            data = true;
          }
        }
        return http.Response(jsonEncode(data), status,
            request: request, headers: {'content-type': 'application/json'});
      }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
          email: 'owner@example.test', password: 'test-only');
      await OnboardingService().bindVerifiedAccount(
        authUserId: client.auth.currentUser!.id,
        email: 'owner@example.test',
        outletIds: ['a'],
      );
      final sync = SyncService(db, client);
      addTearDown(sync.dispose);
      if (missingProfiles) {
        await sync.syncAll();
        expect(productUploads, 1);
        expect((await db.productDao.getProduct('coffee'))!.isSynced, isTrue);
        expect(sync.status.phase, SyncPhase.failed);
        return;
      }
      await enqueueInternalUsage(
          db: db,
          outletId: 'a',
          purpose: 'rnd',
          id: 'fixed-use',
          cart: const Cart(items: [
            CartItem(
                productId: 'coffee',
                productName: 'Kopi',
                unitPrice: 20000,
                unitCogs: 5000)
          ]));
      final queue = (await db.syncDao.getPending()).single;
      for (var attempt = 0; attempt < 6; attempt++) {
        await db.syncDao.incrementRetry(queue.id, 'offline');
      }
      await sync.syncAll();
      expect(sync.status.phase, SyncPhase.failed);
      expect(await db.syncDao.getPendingCount(), 1);
      expect((await db.productDao.getProduct('coffee'))!.stock, '9.0');
      failUsage = false;
      await sync.syncAll();
      expect(sync.status.phase, SyncPhase.synced);
      expect(await db.syncDao.getPendingCount(), 0);
      expect((await db.productDao.getProduct('coffee'))!.stock, '9.0');
      expect(calls.length, 2);
      expect(calls.first, calls.last,
          reason: 'retry uses exactly the same financial request');
      expect(await db.select(db.orders).get(), isEmpty);
    });
  }
}

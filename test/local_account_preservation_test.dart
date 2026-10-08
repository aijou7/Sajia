import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_mobile/core/onboarding_service.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final service = OnboardingService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.outlets).insert(OutletsCompanion.insert(
          id: 'local-outlet',
          name: 'Cafe',
          licenseKey: 'PRO',
        ));
    await db.into(db.orders).insert(OrdersCompanion.insert(
          id: 'sale-1',
          outletId: 'local-outlet',
          orderNumber: '001',
          type: 'takeaway',
          status: 'paid',
          cashierId: 'owner',
          cashierName: 'Owner',
          total: const Value('331420'),
        ));
    await service.bindVerifiedAccount(
      authUserId: 'owner-a',
      email: 'a@example.test',
      outletIds: ['local-outlet'],
    );
    await service.saveCurrentOutletId('local-outlet');
    await service.markSetupDone();
  });
  tearDown(() => db.close());

  Future<void> expectSalePreserved() async {
    final sale = (await db.select(db.orders).get()).single;
    expect(sale.total, '331420');
    expect(sale.isSynced, isFalse);
  }

  test('email logout and same-owner OTP preparation preserve unsynced sales',
      () async {
    await service.resetSetup();
    expect(await service.isSetupDone(), isFalse);
    expect(await service.getVerifiedAuthUserId(), 'owner-a');
    expect(await service.getSavedOwnerEmail(), 'a@example.test');
    expect(await service.getVerifiedOwnerOutletIds(), {'local-outlet'});
    expect(await service.getCurrentOutletId(), 'local-outlet');
    await service.prepareLocalAccount(
      database: db,
      authUserId: 'owner-a',
      email: 'a@example.test',
    );
    await expectSalePreserved();
  });

  test('different owner is blocked without deleting or rebinding local data',
      () async {
    await service.resetSetup();
    await expectLater(
        service.prepareLocalAccount(
          database: db,
          authUserId: 'owner-b',
          email: 'b@example.test',
        ),
        throwsA(isA<LocalDataSafetyException>()));
    expect(await service.getVerifiedAuthUserId(), 'owner-a');
    await expectSalePreserved();
  });

  test('remote scope mismatch preserves the database and pending queue',
      () async {
    await db.syncDao.enqueue(
        tableName: 'orders',
        recordId: 'sale-1',
        operation: 'update',
        payload: const {'outlet_id': 'local-outlet'});
    await expectLater(db.requireLocalOutletScope({'different-outlet'}),
        throwsA(isA<LocalDataSafetyException>()));
    await expectSalePreserved();
    expect(await db.syncDao.getPendingCount(), 1);
    expect(await db.pendingFinancialChanges(), 1);
  });

  test('older logout with erased binding requires matching server ownership',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    await prefs.remove('verified_owner_outlet_ids');
    await service.prepareLocalAccount(
      database: db,
      authUserId: 'owner-a',
      email: 'a@example.test',
      verifyLegacyOutletScope: () async => {'local-outlet'},
    );
    expect(await service.getVerifiedAuthUserId(), 'owner-a');
    await expectSalePreserved();
  });

  test('unknown owner is not reclaimed by a partial or empty server scope',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    for (final scope in [
      <String>{},
      {'another-outlet'}
    ]) {
      await expectLater(
          service.prepareLocalAccount(
            database: db,
            authUserId: 'owner-b',
            email: 'b@example.test',
            verifyLegacyOutletScope: () async => scope,
          ),
          throwsA(isA<LocalDataSafetyException>()));
      expect(await service.getVerifiedAuthUserId(), isNull);
      await expectSalePreserved();
    }
  });

  test('unbound orphaned sales are not treated as an empty installation',
      () async {
    await db.delete(db.outlets).go();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    expect(await db.hasBusinessData(), isTrue);
    await expectLater(
        service.prepareLocalAccount(
          database: db,
          authUserId: 'owner-b',
          email: 'b@example.test',
        ),
        throwsA(isA<LocalDataSafetyException>()));
    await expectSalePreserved();
  });

  test('queue-only local data cannot be rebound without server ownership',
      () async {
    await db.delete(db.orders).go();
    await db.delete(db.outlets).go();
    await db.syncDao.enqueue(
      tableName: 'internal_usage',
      recordId: 'usage-1',
      operation: 'consume',
      payload: {'outlet_id': 'local-outlet'},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    expect(await db.hasBusinessData(), isTrue);
    await expectLater(
      service.prepareLocalAccount(
        database: db,
        authUserId: 'owner-b',
        email: 'b@example.test',
        verifyLegacyOutletScope: () async => {'another-outlet'},
      ),
      throwsA(isA<LocalDataSafetyException>()),
    );
    expect(await service.getVerifiedAuthUserId(), isNull);
    expect(await db.syncDao.getPendingCount(), 1);
  });

  test(
      'unattributed legacy queue cannot prove ownership even with matching scope',
      () async {
    await db.syncDao.enqueue(
      tableName: 'products',
      recordId: 'old-product',
      operation: 'delete',
      payload: {},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    await expectLater(
      service.prepareLocalAccount(
        database: db,
        authUserId: 'owner-a',
        email: 'a@example.test',
        verifyLegacyOutletScope: () async => {'local-outlet'},
      ),
      throwsA(isA<LocalDataSafetyException>()),
    );
    expect(await service.getVerifiedAuthUserId(), isNull);
    expect(await db.syncDao.getPendingCount(), 1);
    await expectSalePreserved();
  });

  test(
      'orphaned order items are not an empty installation or provable legacy scope',
      () async {
    await db.delete(db.orders).go();
    await db.delete(db.outlets).go();
    await db.into(db.orderItems).insert(OrderItemsCompanion.insert(
          id: 'orphan-item',
          orderId: 'missing-sale',
          productId: 'coffee',
          productName: 'Kopi',
          unitPrice: '30000',
          quantity: '1',
          subtotal: '30000',
        ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_auth_user_id');
    expect(await db.hasBusinessData(), isTrue);
    await expectLater(
      service.prepareLocalAccount(
        database: db,
        authUserId: 'owner-b',
        email: 'b@example.test',
        verifyLegacyOutletScope: () async => {'another-outlet'},
      ),
      throwsA(isA<LocalDataSafetyException>()),
    );
    expect(await db.select(db.orderItems).get(), hasLength(1));
    expect(await service.getVerifiedAuthUserId(), isNull);
  });

  test('an empty installation may bind a new account without keeping old scope',
      () async {
    await db.delete(db.orders).go();
    await db.delete(db.outlets).go();
    await service.prepareLocalAccount(
      database: db,
      authUserId: 'owner-b',
      email: 'b@example.test',
    );
    expect(await service.getVerifiedAuthUserId(), 'owner-b');
    expect(await service.getVerifiedOwnerOutletIds(), isEmpty);
  });
}

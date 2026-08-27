import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/utils.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('PIN lookup is restricted to the verified owner outlet scope', () async {
    for (final outletId in ['owner-a-outlet', 'owner-b-outlet']) {
      await database.into(database.outlets).insert(
            OutletsCompanion.insert(
              id: outletId,
              name: outletId,
              licenseKey: 'FREE',
            ),
          );
      await database.sessionDao.upsertUser(
        UsersCompanion.insert(
          id: 'user-$outletId',
          name: 'Owner',
          pin: 'same-looking-pin-hash',
          role: 'owner',
          outletId: outletId,
          isSynced: const Value(true),
        ),
      );
    }

    final ownerAUsers =
        await database.sessionDao.getActiveUsersForOutlets({'owner-a-outlet'});

    expect(ownerAUsers, hasLength(1));
    expect(ownerAUsers.single.id, 'user-owner-a-outlet');
  });

  test('switching verified owner removes previous business and pending writes',
      () async {
    for (final outletId in ['owner-a-outlet', 'owner-b-outlet']) {
      await database.into(database.outlets).insert(
            OutletsCompanion.insert(
              id: outletId,
              name: outletId,
              licenseKey: 'FREE',
            ),
          );
      await database.sessionDao.upsertUser(
        UsersCompanion.insert(
          id: 'user-$outletId',
          name: 'Owner',
          pin: 'pin-$outletId',
          role: 'owner',
          outletId: outletId,
        ),
      );
      await database.productDao.upsertProduct(
        ProductsCompanion.insert(
          id: 'product-$outletId',
          outletId: outletId,
          name: 'Product $outletId',
          price: '10000',
        ),
      );
    }
    await database.syncDao.enqueue(
      tableName: 'products',
      recordId: 'product-owner-a-outlet',
      operation: 'update',
      payload: const {'outlet_id': 'owner-a-outlet'},
    );

    await database.retainOnlyOutlets({'owner-b-outlet'});

    expect(
      (await database.select(database.outlets).get()).map((row) => row.id),
      ['owner-b-outlet'],
    );
    expect(
      (await database.select(database.users).get()).map((row) => row.id),
      ['user-owner-b-outlet'],
    );
    expect(
      (await database.select(database.products).get()).map((row) => row.id),
      ['product-owner-b-outlet'],
    );
    expect(await database.syncDao.getPending(), isEmpty);
  });

  test('verified email recovery can create a new owner PIN locally', () async {
    for (final outletId in ['owner-outlet', 'owner-branch']) {
      await database.into(database.outlets).insert(
            OutletsCompanion.insert(
              id: outletId,
              name: outletId,
              licenseKey: 'FREE',
            ),
          );
    }

    const rawPin = '246810';
    await database.sessionDao.upsertUser(
      UsersCompanion.insert(
        id: 'verified-auth-user',
        name: 'Owner',
        pin: PinHasher.hash(rawPin, 'owner-outlet'),
        role: 'owner',
        outletId: 'owner-outlet',
      ),
    );

    final users = await database.sessionDao.getActiveUsersForOutlets(
      {'owner-outlet', 'owner-branch'},
    );

    expect(users, hasLength(1));
    expect(users.single.id, 'verified-auth-user');
    expect(users.single.role, 'owner');
    expect(
      PinHasher.verify(rawPin, users.single.outletId, users.single.pin),
      isTrue,
    );
    expect(await database.sessionDao.getUnsyncedUsers(), hasLength(1));
  });
}

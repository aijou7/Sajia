import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('deleting a restaurant table queues one durable tombstone payload',
      () async {
    await database.orderDao.upsertTable(
      RestaurantTablesCompanion.insert(
        id: 'table-1',
        outletId: 'outlet-1',
        tableLabel: 'Meja 1',
      ),
    );

    await database.orderDao.deleteTable('table-1');
    await database.orderDao.deleteTable('table-1');

    final tables = await database.select(database.restaurantTables).get();
    final pending = await database.syncDao.getPending();
    final deletes = pending
        .where(
          (item) =>
              item.syncTableName == 'restaurant_tables' &&
              item.recordId == 'table-1' &&
              item.operation == 'delete',
        )
        .toList();

    expect(tables, isEmpty);
    expect(deletes, hasLength(1));
    expect(jsonDecode(deletes.single.payload), {'outlet_id': 'outlet-1'});
  });

  test('remote restaurant table tombstone does not create a delete echo',
      () async {
    await database.orderDao.upsertTable(
      RestaurantTablesCompanion.insert(
        id: 'table-remote-delete',
        outletId: 'outlet-1',
        tableLabel: 'Teras',
      ),
    );

    await database.orderDao.deleteTable(
      'table-remote-delete',
      enqueueSync: false,
    );

    expect(await database.syncDao.getPending(), isEmpty);
  });

  test('replacing outlet access queues only removed relationships', () async {
    await database.sessionDao.replaceUserOutletAccess(
      'manager-1',
      ['outlet-a', 'outlet-b'],
    );
    await database.sessionDao.replaceUserOutletAccess(
      'manager-1',
      ['outlet-a'],
    );
    await database.sessionDao.replaceUserOutletAccess(
      'manager-1',
      ['outlet-a'],
    );

    final outletIds = await database.sessionDao.getUserOutletIds('manager-1');
    final pending = await database.syncDao.getPending();
    final deletes = pending
        .where(
          (item) =>
              item.syncTableName == 'user_outlet_accesses' &&
              item.recordId == 'manager-1_outlet-b' &&
              item.operation == 'delete',
        )
        .toList();

    expect(outletIds, ['outlet-a']);
    expect(deletes, hasLength(1));
    expect(jsonDecode(deletes.single.payload), {
      'outlet_id': 'outlet-b',
      'user_id': 'manager-1',
    });
  });

  test('restoring an unsent outlet assignment cancels its queued delete',
      () async {
    await database.sessionDao.replaceUserOutletAccess(
      'manager-1',
      ['outlet-a'],
    );
    await database.sessionDao.replaceUserOutletAccess('manager-1', const []);
    await database.sessionDao.replaceUserOutletAccess(
      'manager-1',
      ['outlet-a'],
    );

    expect(
      await database.sessionDao.getUserOutletIds('manager-1'),
      ['outlet-a'],
    );
    expect(
      (await database.syncDao.getPending()).where(
        (item) =>
            item.syncTableName == 'user_outlet_accesses' &&
            item.recordId == 'manager-1_outlet-a' &&
            item.operation == 'delete',
      ),
      isEmpty,
    );
  });
}

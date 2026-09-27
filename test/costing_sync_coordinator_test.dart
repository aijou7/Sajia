import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/local/app_database.dart';
import 'package:pos_mobile/data/sync/costing_sync_coordinator.dart';
import 'package:pos_mobile/domain/costing.dart';

CostingComponent _line(String id, {double price = 100000}) => CostingComponent(
      id: id,
      outletId: 'outlet',
      productId: 'coffee',
      materialName: id,
      packageQuantity: 1,
      packageUnit: CostingUnit.kilogram,
      packagePrice: price,
      recipeQuantity: 10,
      recipeUnit: CostingUnit.gram,
      updatedAt: DateTime(2026, 9, 27),
    );

void main() {
  test('managed recipe skips queued upserts and uses exact server snapshot',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = CostingSyncCoordinator(database);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('beans'), _line('milk')],
    );
    final managed = await coordinator.refreshManagedProfiles(
      () async => {'coffee': 'outlet'},
    );
    var uploadCount = 0;
    for (final component in await database.costingDao.getUnsynced()) {
      final pushed = await coordinator.pushIfUnmanaged(
        component: component,
        managedProductIds: managed,
        upload: (_) async {
          uploadCount++;
        },
      );
      expect(pushed, isFalse);
    }
    expect(uploadCount, 0);

    await coordinator.applyRemoteSnapshot(
      managedProductIds: managed,
      remoteComponents: [_line('milk', price: 23000)],
    );
    final recipe = await database.costingDao.getForProduct('coffee');
    expect(recipe.map((line) => line.id).toList(), ['milk']);
    expect(recipe.single.packagePrice, 23000);
    expect(await database.costingDao.getUnsynced(), isEmpty);
  });

  test('unmanaged recipe uploads and deletes through the legacy path',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = CostingSyncCoordinator(database);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('beans'), _line('milk')],
    );
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('beans')],
    );
    final uploaded = <String>[];
    final bean = (await database.costingDao.getUnsynced()).single;
    final pushed = await coordinator.pushIfUnmanaged(
      component: bean,
      managedProductIds: const <String>{},
      upload: (line) async {
        uploaded.add(line.id);
      },
    );
    expect(pushed, isTrue);
    expect(uploaded, ['beans']);
    expect(await database.costingDao.getUnsynced(), isEmpty);

    final pending = (await database.syncDao.getPending()).single;
    final deleted = <String>[];
    await coordinator.resolvePendingDelete(
      queueId: pending.id,
      componentId: pending.recordId,
      productId: 'coffee',
      managedProductIds: const <String>{},
      findRemoteProductId: (_) async => throw StateError('not needed'),
      deleteRemote: (id) async {
        deleted.add(id);
      },
    );
    expect(deleted, ['milk']);
    expect(await database.syncDao.getPending(), isEmpty);
  });

  test('managed delete is resolved without touching server recipe', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = CostingSyncCoordinator(database);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('milk')],
    );
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: const [],
    );
    final pending = (await database.syncDao.getPending()).single;
    var remoteDeletes = 0;
    await coordinator.resolvePendingDelete(
      queueId: pending.id,
      componentId: pending.recordId,
      productId: 'coffee',
      managedProductIds: {'coffee'},
      findRemoteProductId: (_) async => throw StateError('not needed'),
      deleteRemote: (_) async {
        remoteDeletes++;
      },
    );
    expect(remoteDeletes, 0);
    expect(await database.syncDao.getPending(), isEmpty);
  });

  test('profile lookup failure keeps cache and prevents recipe writes',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = CostingSyncCoordinator(database);
    await database.costingDao.replaceManagedProfiles({'coffee': 'outlet'});
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('beans')],
    );
    var uploadCount = 0;

    Future<void> attemptSync() async {
      final managed = await coordinator.refreshManagedProfiles(
        () async => throw StateError('network unavailable'),
      );
      for (final component in await database.costingDao.getUnsynced()) {
        await coordinator.pushIfUnmanaged(
          component: component,
          managedProductIds: managed,
          upload: (_) async {
            uploadCount++;
          },
        );
      }
    }

    await expectLater(attemptSync(), throwsStateError);
    expect(await database.costingDao.isOwnerManagedProduct('coffee'), isTrue);
    expect((await database.costingDao.getUnsynced()).length, 1);
    expect(uploadCount, 0);
  });

  test('guard race leaves local edit pending until managed pull resolves it',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = CostingSyncCoordinator(database);
    await database.costingDao.replaceForProduct(
      outletId: 'outlet',
      productId: 'coffee',
      components: [_line('old')],
    );
    final old = (await database.costingDao.getUnsynced()).single;

    await expectLater(
      coordinator.pushIfUnmanaged(
        component: old,
        managedProductIds: const <String>{},
        upload: (_) async =>
            throw StateError('OWNER_COSTING_MANAGED_IN_DASHBOARD'),
      ),
      throwsStateError,
    );
    expect((await database.costingDao.getUnsynced()).single.id, 'old');

    final managed = await coordinator.refreshManagedProfiles(
      () async => {'coffee': 'outlet'},
    );
    await coordinator.applyRemoteSnapshot(
      managedProductIds: managed,
      remoteComponents: [_line('new')],
    );
    expect((await database.costingDao.getForProduct('coffee')).single.id,
        'new');
    expect(await database.costingDao.getUnsynced(), isEmpty);
  });
}

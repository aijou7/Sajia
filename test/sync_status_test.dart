import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/data/sync/sync_service.dart';

void main() {
  test('SyncStatus reports pending local changes', () {
    const status = SyncStatus(
      phase: SyncPhase.offline,
      pendingCount: 3,
    );

    expect(status.hasPending, isTrue);
    expect(status.phase, SyncPhase.offline);
    expect(status.pendingCount, 3);
  });

  test('SyncStatus defaults to idle without pending changes', () {
    const status = SyncStatus();

    expect(status.phase, SyncPhase.idle);
    expect(status.hasPending, isFalse);
    expect(status.lastSyncedAt, isNull);
  });
}

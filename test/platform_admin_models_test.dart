import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/features/owner_web/platform_admin_page.dart';

void main() {
  test('parses platform entitlement account rows', () {
    final accounts = PlatformAdminData.accountsFromRpc([
      {
        'owner_email': 'owner@example.com',
        'outlet_count': 2,
        'pro_outlet_count': 2,
        'cloud_outlet_count': 2,
        'plan_code': 'CLOUD',
        'cloud_expiry': '2026-09-30T23:59:59Z',
        'outlets': [
          {'id': 'outlet-1', 'name': 'Pusat', 'license_key': 'PRO'},
          {'id': 'outlet-2', 'name': 'Cabang', 'license_key': 'PRO'},
        ],
      },
    ]);

    expect(accounts, hasLength(1));
    expect(accounts.single.ownerEmail, 'owner@example.com');
    expect(accounts.single.planLabel, 'Cloud');
    expect(accounts.single.outlets, hasLength(2));
    expect(accounts.single.cloudExpiry, isNotNull);
  });

  test('derives audit destination plan from the server snapshot', () {
    final audit = PlatformAdminData.auditFromRpc([
      {
        'owner_email': 'owner@example.com',
        'previous_state': [
          {'license_key': 'FREE', 'cloud_expiry': null},
        ],
        'next_state': [
          {
            'license_key': 'PRO',
            'cloud_expiry': '2099-01-01T00:00:00Z',
          },
        ],
      },
    ]);

    expect(audit.single.nextPlan, 'Cloud');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_mobile/core/app_update_service.dart';

void main() {
  test('compares semantic app versions numerically', () {
    expect(AppVersion.compare('1.0.9', '1.0.10'), lessThan(0));
    expect(AppVersion.compare('v1.2', '1.2.0'), equals(0));
    expect(AppVersion.compare('2.0.0', '1.99.99'), greaterThan(0));
  });

  test('parses a trusted ABI manifest and mandatory minimum version', () {
    final info = AppUpdateInfo.fromManifest(
      {
        'latest_version': '1.0.23',
        'minimum_version': '1.0.20',
        'android': {
          'variants': {
            'v8a': {
              'url':
                  'https://github.com/aijou7/Sajia/releases/download/v1.0.23/Sajia-v1.0.23-v8a.apk',
              'sha256':
                  '49b73174251f8b2d671e5db5897cc510b5d5ee4c9748df2333a759011293480d',
            },
          },
        },
      },
      abi: 'v8a',
      currentVersion: '1.0.19',
    );

    expect(info.latestVersion, '1.0.23');
    expect(info.abi, 'v8a');
    expect(info.isMandatory, isTrue);
  });

  test('rejects APK URLs outside trusted GitHub hosts', () {
    expect(
      () => AppUpdateInfo.fromManifest(
        {
          'latest_version': '1.0.23',
          'android': {
            'variants': {
              'v7a': {
                'url': 'https://example.com/sajia.apk',
                'sha256':
                    '16407c2b3cb079d8d0440d5a1f99e9c37103d5151f7276883a42d7ecfc943073',
              },
            },
          },
        },
        abi: 'v7a',
        currentVersion: '1.0.22',
      ),
      throwsFormatException,
    );
  });
}

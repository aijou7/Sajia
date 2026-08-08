import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('owner email is canonicalized before authentication', () {
    expect(
      OnboardingService().normalizeEmail('  Owner+Cabang@Example.COM  '),
      'owner+cabang@example.com',
    );
  });

  test('OTP resend cooldown only applies to the same normalized email',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_otp_email', 'owner@example.com');
    await prefs.setInt(
      'last_otp_sent_at',
      DateTime.now()
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch,
    );

    final service = OnboardingService();
    final sameEmail = await service.otpCooldownRemaining(
      ' OWNER@EXAMPLE.COM ',
    );
    final differentEmail = await service.otpCooldownRemaining(
      'other@example.com',
    );

    expect(sameEmail.inSeconds, inInclusiveRange(48, 50));
    expect(differentEmail, Duration.zero);
  });

  test('expired OTP cooldown is cleared', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_otp_email', 'owner@example.com');
    await prefs.setInt(
      'last_otp_sent_at',
      DateTime.now()
          .subtract(const Duration(minutes: 2))
          .millisecondsSinceEpoch,
    );

    expect(
      await OnboardingService().otpCooldownRemaining('owner@example.com'),
      Duration.zero,
    );
  });

  test('verified owner binding keeps auth identity and outlet scope together',
      () async {
    final service = OnboardingService();
    await service.bindVerifiedAccount(
      authUserId: 'auth-owner-b',
      email: ' OWNER-B@EXAMPLE.COM ',
      outletIds: ['outlet-b', 'outlet-b', 'outlet-c'],
    );

    expect(await service.getVerifiedAuthUserId(), 'auth-owner-b');
    expect(await service.getSavedOwnerEmail(), 'owner-b@example.com');
    expect(
      await service.getVerifiedOwnerOutletIds(),
      {'outlet-b', 'outlet-c'},
    );
  });
}

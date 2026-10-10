import '../data/local/app_database.dart';
import 'onboarding_service.dart';

/// Native-only guards. Shared OTP/login code must not import Drift's FFI
/// database, because the owner dashboard also uses it in the browser.
extension LocalAccountSafety on OnboardingService {
  /// Only a verified email session may bind local data. A different account or
  /// unproven legacy binding must never trigger an automatic database wipe.
  Future<void> prepareLocalAccount({
    required AppDatabase database,
    required String authUserId,
    required String email,
    Future<Set<String>> Function()? verifyLegacyOutletScope,
  }) async {
    final hasData = await database.hasBusinessData();
    final boundId = await getVerifiedAuthUserId();
    Set<String>? scope;
    if (hasData && boundId != authUserId) {
      if (boundId != null || verifyLegacyOutletScope == null) {
        throw const LocalDataSafetyException(
          'Perangkat masih menyimpan data akun lain atau belum terverifikasi. '
          'Data tidak dihapus. Masuk dengan akun pemilik data lokal.',
        );
      }
      // Older logout versions erased the binding. Reclaim only after the
      // authenticated server proves every local outlet belongs to this owner.
      scope = await verifyLegacyOutletScope();
      await database.requireLocalOutletScope(scope,
          requireFullAttribution: true);
    } else if (!hasData && boundId != authUserId) {
      scope = const <String>{};
    }
    await bindVerifiedAccount(
      authUserId: authUserId,
      email: email,
      outletIds: scope,
    );
  }

  Future<void> requireLocalAccount({
    required AppDatabase database,
    required String authUserId,
  }) async {
    if (await database.hasBusinessData() &&
        await getVerifiedAuthUserId() != authUserId) {
      throw const LocalDataSafetyException(
        'Akun Cloud tidak cocok dengan pemilik data lokal. '
        'Data tidak dihapus; verifikasi kembali akun pemilik.',
      );
    }
  }
}

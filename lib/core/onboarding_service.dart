import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingService {
  static final OnboardingService _instance = OnboardingService._internal();
  factory OnboardingService() => _instance;
  OnboardingService._internal();

  static const _keyIsSetupDone = 'onboarding_done';
  static const _keyOwnerEmail = 'owner_email';
  static const _keyCurrentOutletId = 'current_outlet_id';
  String? lastOtpError;

  SupabaseClient get _supabase => Supabase.instance.client;
  Future<bool> accountExists(String email) async {
    final normalizedEmail = normalizeEmail(email);
    try {
      final response = await _supabase
          .from('outlets')
          .select('id')
          .eq('owner_email', normalizedEmail)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getOutletIdByEmail(String email) async {
    final normalizedEmail = normalizeEmail(email);
    try {
      final response = await _supabase
          .from('outlets')
          .select('id')
          .eq('owner_email', normalizedEmail)
          .maybeSingle();
      return response?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsSetupDone) ?? false;
  }

  Future<void> markSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSetupDone, true);
  }

  Future<String?> getCurrentOutletId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrentOutletId);
  }

  Future<void> saveCurrentOutletId(String outletId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentOutletId, outletId);
  }

  Future<String?> getSavedOwnerEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOwnerEmail);
  }

  Future<void> saveOwnerEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOwnerEmail, email);
  }

  // ── OTP via Supabase Auth ─────────────────────

  String normalizeEmail(String email) => email.trim().toLowerCase();

  Future<OtpResult> sendOtp(
    String email, {
    required bool shouldCreateUser,
  }) async {
    final normalizedEmail = normalizeEmail(email);
    try {
      lastOtpError = null;
      await _supabase.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: shouldCreateUser,
      );
      await saveOwnerEmail(normalizedEmail);
      return OtpResult.sent;
    } on AuthException catch (e) {
      lastOtpError = e.message;
      final message = e.message.toLowerCase();
      if (message.contains('rate limit') || message.contains('too many')) {
        return OtpResult.rateLimited;
      }
      return OtpResult.failed;
    } catch (e) {
      lastOtpError = e.toString();
      return OtpResult.failed;
    }
  }

  Future<List<Map<String, dynamic>>> getAuthenticatedOwnerOutlets() async {
    final response = await _supabase.rpc('get_authenticated_owner_outlets');
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<OtpVerifyResult> verifyOtp(
    String email,
    String otp,
  ) async {
    final normalizedEmail = normalizeEmail(email);
    final normalizedOtp = otp.replaceAll(RegExp(r'\D'), '');
    // Supabase email OTP uses OtpType.email for both first-time signup and
    // returning-user login. OtpType.signup is deprecated for email OTP and can
    // produce misleading expired/invalid errors after a successful send.
    try {
      lastOtpError = null;
      final response = await _supabase.auth.verifyOTP(
        email: normalizedEmail,
        token: normalizedOtp,
        type: OtpType.email,
      );
      if (response.user != null || response.session != null) {
        return OtpVerifyResult.success;
      }
      return OtpVerifyResult.invalid;
    } on AuthException catch (e) {
      lastOtpError = e.message;
      final message = e.message.toLowerCase();
      if (message.contains('expired')) {
        return OtpVerifyResult.expired;
      }
      return OtpVerifyResult.invalid;
    } catch (e) {
      lastOtpError = e.toString();
      return OtpVerifyResult.failed;
    }
  }

  Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSetupDone, false);
    await prefs.remove(_keyCurrentOutletId);
  }
}

enum OtpResult { sent, rateLimited, failed }

enum OtpVerifyResult { success, invalid, expired, failed }

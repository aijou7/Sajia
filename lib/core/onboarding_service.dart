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
    try {
      final response = await _supabase
          .from('outlets')
          .select('id')
          .eq('owner_email', email)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getOutletIdByEmail(String email) async {
    try {
      final response = await _supabase
          .from('outlets')
          .select('id')
          .eq('owner_email', email)
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

  Future<OtpResult> sendOtp(String email,
      {required bool shouldCreateUser}) async {
    try {
      lastOtpError = null;
      await _supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: shouldCreateUser,
      );
      await saveOwnerEmail(email);
      return OtpResult.sent;
    } on AuthException catch (e) {
      lastOtpError = e.message;
      if (e.message.contains('rate limit')) return OtpResult.rateLimited;
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

  Future<OtpVerifyResult> verifyOtp(String email, String otp) async {
    try {
      final res = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );
      if (res.user != null) return OtpVerifyResult.success;
      return OtpVerifyResult.invalid;
    } on AuthException catch (e) {
      if (e.message.contains('expired')) return OtpVerifyResult.expired;
      return OtpVerifyResult.invalid;
    } catch (_) {
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

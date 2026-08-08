import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingService {
  static final OnboardingService _instance = OnboardingService._internal();
  factory OnboardingService() => _instance;
  OnboardingService._internal();

  static const _keyIsSetupDone = 'onboarding_done';
  static const _keyOwnerEmail = 'owner_email';
  static const _keyCurrentOutletId = 'current_outlet_id';
  static const _keyLastOtpEmail = 'last_otp_email';
  static const _keyLastOtpSentAt = 'last_otp_sent_at';
  static const otpCooldown = Duration(seconds: 60);
  String? lastOtpError;
  Duration? lastOtpRetryAfter;

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

  Future<Duration> otpCooldownRemaining(String email) async {
    final normalizedEmail = normalizeEmail(email);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyLastOtpEmail) != normalizedEmail) {
      return Duration.zero;
    }
    final sentAtValue = prefs.getInt(_keyLastOtpSentAt);
    if (sentAtValue == null) return Duration.zero;
    final sentAt = DateTime.fromMillisecondsSinceEpoch(sentAtValue);
    final remaining = otpCooldown - DateTime.now().difference(sentAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _rememberOtpSent(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastOtpEmail, email);
    await prefs.setInt(
      _keyLastOtpSentAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Duration _retryAfterFromMessage(String message) {
    final match = RegExp(
      r'(?:after|in|wait)\s+(\d+)\s*(?:second|seconds|sec)',
      caseSensitive: false,
    ).firstMatch(message);
    final seconds = int.tryParse(match?.group(1) ?? '');
    if (seconds == null) return otpCooldown;
    return Duration(seconds: seconds.clamp(1, 3600));
  }

  bool _looksLikeNetworkFailure(Object error) {
    final message = error.toString().toLowerCase();
    return error is TimeoutException ||
        message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout');
  }

  Future<OtpResult> sendOtp(
    String email, {
    required bool shouldCreateUser,
  }) async {
    final normalizedEmail = normalizeEmail(email);
    try {
      lastOtpError = null;
      lastOtpRetryAfter = null;
      final cooldown = await otpCooldownRemaining(normalizedEmail);
      if (cooldown > Duration.zero) {
        lastOtpRetryAfter = cooldown;
        return OtpResult.cooldown;
      }
      await _supabase.auth
          .signInWithOtp(
            email: normalizedEmail,
            shouldCreateUser: shouldCreateUser,
          )
          .timeout(const Duration(seconds: 25));
      await _rememberOtpSent(normalizedEmail);
      await saveOwnerEmail(normalizedEmail);
      return OtpResult.sent;
    } on AuthException catch (e) {
      lastOtpError = e.message;
      final message = e.message.toLowerCase();
      if (message.contains('rate limit') || message.contains('too many')) {
        lastOtpRetryAfter = _retryAfterFromMessage(message);
        return OtpResult.rateLimited;
      }
      if (!shouldCreateUser &&
          (message.contains('user not found') ||
              message.contains('signup') ||
              message.contains('not registered'))) {
        return OtpResult.accountNotFound;
      }
      if (_looksLikeNetworkFailure(e)) return OtpResult.networkUnavailable;
      return OtpResult.failed;
    } catch (e) {
      lastOtpError = e.toString();
      if (_looksLikeNetworkFailure(e)) return OtpResult.networkUnavailable;
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
      if (normalizedOtp.length != 6) return OtpVerifyResult.invalid;
      final response = await _supabase.auth
          .verifyOTP(
            email: normalizedEmail,
            token: normalizedOtp,
            type: OtpType.email,
          )
          .timeout(const Duration(seconds: 25));
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
      if (message.contains('rate limit') || message.contains('too many')) {
        return OtpVerifyResult.rateLimited;
      }
      return OtpVerifyResult.invalid;
    } catch (e) {
      lastOtpError = e.toString();
      if (_looksLikeNetworkFailure(e)) {
        return OtpVerifyResult.networkUnavailable;
      }
      return OtpVerifyResult.failed;
    }
  }

  Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSetupDone, false);
    await prefs.remove(_keyCurrentOutletId);
  }
}

enum OtpResult {
  sent,
  cooldown,
  rateLimited,
  accountNotFound,
  networkUnavailable,
  failed,
}

enum OtpVerifyResult {
  success,
  invalid,
  expired,
  rateLimited,
  networkUnavailable,
  failed,
}

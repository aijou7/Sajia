import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_integrity_service.dart';
import '../data/local/app_database.dart';

class PlanCheckoutSession {
  final String checkoutUrl;
  final String successUrl;
  final int amount;
  final String currency;

  const PlanCheckoutSession({
    required this.checkoutUrl,
    required this.successUrl,
    required this.amount,
    required this.currency,
  });
}

class SajiaPlanStatus {
  final bool isPro;
  final bool isCloud;
  final String status;
  final DateTime? expiresAt;

  const SajiaPlanStatus({
    required this.isPro,
    required this.isCloud,
    required this.status,
    required this.expiresAt,
  });
}

class SajiaPlanService {
  final SupabaseClient _supabase;

  const SajiaPlanService(this._supabase);

  Future<PlanCheckoutSession> createCheckout({
    required String outletId,
    required String outletName,
    required String planCode,
  }) async {
    final ownerEmail = _supabase.auth.currentUser?.email;
    if (ownerEmail == null || ownerEmail.trim().isEmpty) {
      throw const SajiaPlanException(
        'Login email owner dulu untuk upgrade paket.',
      );
    }
    final integrityProof = await const AppIntegrityService().createProof(
      action: 'create_plan_checkout',
      payload: {
        'outlet_id': outletId,
        'plan_code': planCode,
      },
    );

    late final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke(
        'create-plan-checkout',
        body: {
          'outlet_id': outletId,
          'outlet_name': outletName,
          'plan_code': planCode,
          'owner_email': ownerEmail,
          'integrity_request_hash': integrityProof.requestHash,
          if (integrityProof.token != null)
            'integrity_token': integrityProof.token,
        },
      );
    } on FunctionException catch (error) {
      throw SajiaPlanException(_functionErrorMessage(error));
    } catch (error) {
      throw SajiaPlanException(_networkErrorMessage(error));
    }

    final data = _asMap(response.data);
    final errorMessage = data['error'];
    if (errorMessage is String && errorMessage.isNotEmpty) {
      throw SajiaPlanException(errorMessage);
    }
    final checkoutUrl = data['checkout_url'] as String?;
    final successUrl = data['success_url'] as String?;
    final amount = data['amount'];
    final currency = data['currency'] as String?;

    if (checkoutUrl == null || successUrl == null || amount is! num) {
      throw const SajiaPlanException('Checkout pembayaran belum siap');
    }
    _validateCheckoutUrl(checkoutUrl);
    _validateSuccessUrl(successUrl);

    return PlanCheckoutSession(
      checkoutUrl: checkoutUrl,
      successUrl: successUrl,
      amount: amount.toInt(),
      currency: currency ?? 'IDR',
    );
  }

  String _functionErrorMessage(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final message = details['error'] ?? details['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (details is String && details.isNotEmpty) return details;
    return 'Payment service error ${error.status}. Cek deploy Edge Function dan secret Midtrans.';
  }

  String _networkErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('timeout')) {
      return 'Koneksi ke payment service gagal. Cek internet lalu coba lagi.';
    }
    return 'Payment service gagal: ${_shortError(text)}';
  }

  String _shortError(String text) {
    final cleaned = text
        .replaceFirst('Exception: ', '')
        .replaceFirst('SajiaPlanException: ', '');
    if (cleaned.length <= 180) return cleaned;
    return '${cleaned.substring(0, 180)}...';
  }

  void _validateCheckoutUrl(String url) {
    final uri = Uri.tryParse(url);
    final allowedHosts = {
      'app.sandbox.midtrans.com',
      'app.midtrans.com',
    };
    if (uri == null ||
        uri.scheme != 'https' ||
        !allowedHosts.contains(uri.host.toLowerCase())) {
      throw const SajiaPlanException(
        'Checkout pembayaran tidak valid. Hubungi support Sajia.',
      );
    }
  }

  void _validateSuccessUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const SajiaPlanException(
        'Callback pembayaran tidak valid. Hubungi support Sajia.',
      );
    }
  }

  Future<SajiaPlanStatus> getStatus(String outletId) async {
    final response = await _supabase.functions.invoke(
      'get-plan-status',
      body: {'outlet_id': outletId},
    );
    final data = _asMap(response.data);
    final errorMessage = data['error'];
    if (errorMessage is String && errorMessage.isNotEmpty) {
      throw SajiaPlanException(errorMessage);
    }
    final expiry = data['expires_at'] as String?;

    return SajiaPlanStatus(
      isPro: data['is_pro'] == true,
      isCloud: data['is_cloud'] == true,
      status: data['status'] as String? ?? 'FREE',
      expiresAt: expiry == null ? null : DateTime.tryParse(expiry),
    );
  }

  Future<SajiaPlanStatus> refreshLocalPlan({
    required AppDatabase database,
    required String outletId,
  }) async {
    final status = await getStatus(outletId);
    await (database.update(database.outlets)
          ..where((outlet) => outlet.id.equals(outletId)))
        .write(
      OutletsCompanion(
        licenseKey: Value(status.isPro ? 'PRO' : 'FREE'),
        licenseExpiry: const Value(null),
        cloudExpiry: Value(status.isCloud ? status.expiresAt : null),
      ),
    );
    return status;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const SajiaPlanException('Respons payment service tidak valid');
  }
}

class SajiaPlanException implements Exception {
  final String message;
  const SajiaPlanException(this.message);

  @override
  String toString() => message;
}

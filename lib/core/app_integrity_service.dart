import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class AppIntegrityProof {
  final String requestHash;
  final String? token;

  const AppIntegrityProof({
    required this.requestHash,
    required this.token,
  });
}

class AppIntegrityService {
  static const _channel = MethodChannel('sajia/system');
  static const _cloudProjectNumber = int.fromEnvironment(
    'PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
    defaultValue: 0,
  );

  const AppIntegrityService();

  bool get isConfigured => _cloudProjectNumber > 0;

  Future<AppIntegrityProof> createProof({
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final requestHash = buildRequestHash(action: action, payload: payload);
    if (!isConfigured || !Platform.isAndroid) {
      return AppIntegrityProof(requestHash: requestHash, token: null);
    }

    await _channel.invokeMethod<bool>('preparePlayIntegrity', {
      'cloudProjectNumber': _cloudProjectNumber,
    });
    final token = await _channel.invokeMethod<String>(
      'requestPlayIntegrityToken',
      {'requestHash': requestHash},
    );
    return AppIntegrityProof(requestHash: requestHash, token: token);
  }

  static String buildRequestHash({
    required String action,
    required Map<String, Object?> payload,
  }) {
    final canonical = SplayTreeMap<String, Object?>.from({
      'action': action,
      ...payload,
    });
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }
}

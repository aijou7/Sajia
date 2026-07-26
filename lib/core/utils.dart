import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

double bottomSheetSafePadding(BuildContext context, {double extra = 24}) {
  final media = MediaQuery.of(context);
  final systemInset = max(media.viewPadding.bottom, media.padding.bottom);
  final navFallback = media.viewInsets.bottom > 0 ? 0.0 : 64.0;
  return media.viewInsets.bottom + max(systemInset, navFallback) + extra;
}

double pageBottomSafePadding(BuildContext context, {double extra = 96}) {
  final media = MediaQuery.of(context);
  final systemInset = max(media.viewPadding.bottom, media.padding.bottom);
  return extra + max(systemInset, 24.0);
}

// ─────────────────────────────────────────────
// ID GENERATOR
// ─────────────────────────────────────────────
class IdGen {
  static final _rand = Random.secure();
  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Generate UUID-like string, contoh: "k7xm2p9q-a1b2-c3d4-e5f6"
  static String uuid() {
    String seg(int len) => List.generate(
          len,
          (_) => _chars[_rand.nextInt(_chars.length)],
        ).join();
    return '${seg(8)}-${seg(4)}-${seg(4)}-${seg(4)}';
  }

  /// Order number: ORD-20241201-0001 (per hari, reset tiap hari)
  static String orderNumber(int sequence) {
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final seq = sequence.toString().padLeft(4, '0');
    return 'ORD-$date-$seq';
  }
}

// ─────────────────────────────────────────────
// CURRENCY FORMATTER (Rupiah)
// ─────────────────────────────────────────────
class Rupiah {
  static final _fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String format(double amount) => _fmt.format(amount);

  static String formatCompact(double amount) {
    if (amount >= 1000000) {
      return 'Rp ${(amount / 1000000).toStringAsFixed(1)}jt';
    }
    if (amount >= 1000) return 'Rp ${(amount / 1000).toStringAsFixed(0)}rb';
    return format(amount);
  }

  /// Parse "Rp 15.000" → 15000.0
  static double parse(String text) {
    final cleaned =
        text.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0;
  }
}

// ─────────────────────────────────────────────
// PIN HASHER
// ─────────────────────────────────────────────
class PinHasher {
  static const _version = 'pin2';
  static const _iterations = 120000;
  static const _hashLength = 32;

  static String hash(String pin, String outletId) {
    final salt = List<int>.generate(16, (_) => IdGen._rand.nextInt(256));
    final digest = _pbkdf2(pin, outletId, salt, _iterations, _hashLength);
    return [
      _version,
      _iterations.toString(),
      base64UrlEncode(salt),
      base64UrlEncode(digest),
    ].join(r'$');
  }

  static bool verify(String pin, String outletId, String storedHash) {
    if (isLegacyHash(storedHash)) {
      return _constantTimeEquals(_legacyHash(pin, outletId), storedHash);
    }

    final parts = storedHash.split(r'$');
    if (parts.length != 4 || parts.first != _version) return false;

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;

    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = _pbkdf2(pin, outletId, salt, iterations, expected.length);
      return _constantTimeBytesEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static bool isLegacyHash(String storedHash) {
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(storedHash);
  }

  static String _legacyHash(String pin, String outletId) {
    final bytes = utf8.encode('$outletId:$pin:pos_fnb_salt');
    return sha256.convert(bytes).toString();
  }

  static List<int> _pbkdf2(
    String pin,
    String outletId,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final blockSalt = [
      ...utf8.encode('sajia-pin:$outletId:'),
      ...salt,
      0,
      0,
      0,
      1,
    ];
    var block = hmac.convert(blockSalt).bytes;
    final result = List<int>.from(block);

    for (var i = 1; i < iterations; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }

    return result.take(length).toList();
  }

  static bool _constantTimeEquals(String a, String b) {
    return _constantTimeBytesEquals(utf8.encode(a), utf8.encode(b));
  }

  static bool _constantTimeBytesEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

// ─────────────────────────────────────────────
// DATE HELPERS
// ─────────────────────────────────────────────
class DateHelper {
  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);

  static DateTime endOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0, 23, 59, 59);

  static String formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  static String formatDate(DateTime dt) =>
      DateFormat('d MMM yyyy', 'id_ID').format(dt);

  static String formatDateTime(DateTime dt) =>
      DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(dt);

  static String formatShort(DateTime dt) => DateFormat('dd/MM/yy').format(dt);
}

// ─────────────────────────────────────────────
// EXTENSIONS
// ─────────────────────────────────────────────
extension DoubleExt on double {
  String get toRupiah => Rupiah.format(this);
  String get toRupiahCompact => Rupiah.formatCompact(this);
}

extension StringExt on String {
  double get toDouble => double.tryParse(this) ?? 0;
  int get toInt => int.tryParse(this) ?? 0;
}

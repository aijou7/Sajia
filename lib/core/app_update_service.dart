import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata for one signed Android APK published with a Kasata release.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.minimumVersion,
    required this.releaseNotes,
    required this.apkUrl,
    required this.sha256,
    required this.abi,
    required this.isMandatory,
  });

  final String latestVersion;
  final String minimumVersion;
  final String releaseNotes;
  final Uri apkUrl;
  final String sha256;
  final String abi;
  final bool isMandatory;

  factory AppUpdateInfo.fromManifest(
    Map<String, dynamic> manifest, {
    required String abi,
    required String currentVersion,
  }) {
    final latestVersion = _requiredString(manifest['latest_version']);
    final minimumVersion =
        _optionalString(manifest['minimum_version']) ?? '0.0.0';
    if (AppVersion.compare(minimumVersion, latestVersion) > 0) {
      throw const FormatException('Batas minimum versi update tidak valid');
    }
    final releaseNotes = _optionalString(manifest['release_notes']) ?? '';
    final android = _mapValue(manifest['android']);
    final variants = _mapValue(android['variants']);
    final variant = _mapValue(variants[abi]);
    final apkUrl = _httpsGithubUri(_requiredString(variant['url']));
    final checksum = _requiredString(variant['sha256']).toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Checksum update tidak valid');
    }
    return AppUpdateInfo(
      latestVersion: latestVersion,
      minimumVersion: minimumVersion,
      releaseNotes: releaseNotes,
      apkUrl: apkUrl,
      sha256: checksum,
      abi: abi,
      isMandatory: AppVersion.compare(currentVersion, minimumVersion) < 0,
    );
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppVersion {
  const AppVersion._();

  static int compare(String left, String right) {
    final a = _parts(left);
    final b = _parts(right);
    for (var index = 0; index < 3; index++) {
      final result = a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return 0;
  }

  static List<int> _parts(String value) {
    final clean = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(clean);
    if (match == null) throw const FormatException('Versi tidak valid');
    return [
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '0') ?? 0,
      int.tryParse(match.group(3) ?? '0') ?? 0,
    ];
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _manifestUrl =
      'https://github.com/aijou7/Sajia/releases/latest/download/Sajia-update.json';
  static const _lastCheckKey = 'sajia_update_last_check';
  static const _checkInterval = Duration(hours: 12);
  static const _channel = MethodChannel('sajia/system');

  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!Platform.isAndroid) return null;

    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final previousCheckMillis = preferences.getInt(_lastCheckKey) ?? 0;
    if (!force &&
        previousCheckMillis > 0 &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(previousCheckMillis)) <
            _checkInterval) {
      return null;
    }

    await preferences.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final abi = await _preferredAbi();
      final manifest = jsonDecode(await _getText(Uri.parse(_manifestUrl)));
      if (manifest is! Map<String, dynamic>) {
        throw const FormatException('Manifest update tidak valid');
      }
      final info = AppUpdateInfo.fromManifest(
        manifest,
        abi: abi,
        currentVersion: packageInfo.version,
      );
      if (AppVersion.compare(packageInfo.version, info.latestVersion) >= 0) {
        return null;
      }
      return info;
    } catch (_) {
      // Update checking must never block login, sync, or offline operation.
      return null;
    }
  }

  Future<File> downloadAndVerify(
    AppUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final cacheDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory('${cacheDirectory.path}/updates');
    await updateDirectory.create(recursive: true);
    final file = File(
      '${updateDirectory.path}/sajia-${info.latestVersion}-${info.abi}.apk',
    );
    if (await file.exists()) await file.delete();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    IOSink? sink;
    try {
      final request = await client.getUrl(info.apkUrl);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.android.package-archive');
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException('Server update mengembalikan ${response.statusCode}');
      }

      sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != info.sha256) {
        await file.delete();
        throw const AppUpdateException('Checksum APK tidak cocok');
      }
      onProgress?.call(1);
      return file;
    } catch (error) {
      await sink?.close();
      if (await file.exists()) await file.delete();
      if (error is AppUpdateException) rethrow;
      throw const AppUpdateException('Download update gagal');
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
  }

  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<void> installApk(File file) async {
    if (!await file.exists()) {
      throw const AppUpdateException('File update tidak ditemukan');
    }
    await _channel.invokeMethod<void>('installApk', {'path': file.path});
  }

  Future<String> _preferredAbi() async {
    final abi = await _channel.invokeMethod<String>('preferredAbi');
    if (abi == 'v7a' || abi == 'v8a') return abi!;
    throw const AppUpdateException('Arsitektur Android belum didukung');
  }

  Future<String> _getText(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException('Manifest update mengembalikan ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

String _requiredString(Object? value) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) throw const FormatException('Field manifest kosong');
  return text;
}

String? _optionalString(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Struktur manifest update tidak valid');
}

Uri _httpsGithubUri(String value) {
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase() ?? '';
  final trustedHost = host == 'github.com' || host.endsWith('.githubusercontent.com');
  if (uri == null || uri.scheme != 'https' || !trustedHost) {
    throw const FormatException('URL APK update tidak dipercaya');
  }
  return uri;
}

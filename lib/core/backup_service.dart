import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:share_plus/share_plus.dart';
import 'brand.dart';
import '../data/local/app_database.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  static const _encryptedFormat = 'sajia_backup_encrypted';
  static const _encryptedVersion = 2;
  static const _pbkdf2Iterations = 210000;
  static const _backupExtension = 'sajiabak';

// ── BACKUP ────────────────────────────────────

  Future<BackupResult> createBackup(
    AppDatabase db,
    String outletId, {
    required String passphrase,
  }) async {
    try {
      if (passphrase.trim().length < 8) {
        return BackupResult.passwordTooShort;
      }

      final allProducts = await (db.select(db.products)
            ..where((p) => p.outletId.equals(outletId)))
          .get();
      final allCategories = await (db.select(db.categories)
            ..where((c) => c.outletId.equals(outletId)))
          .get();
      final allOrders = await (db.select(db.orders)
            ..where((o) => o.outletId.equals(outletId)))
          .get();
      final allUsers = await db.sessionDao.getUsers(outletId);
      final allAccesses = await (db.select(db.userOutletAccesses)
            ..where((access) => access.outletId.equals(outletId)))
          .get();
      final allTables = await (db.select(db.restaurantTables)
            ..where((t) => t.outletId.equals(outletId)))
          .get();
      final outlet = await (db.select(db.outlets)
            ..where((o) => o.id.equals(outletId)))
          .getSingleOrNull();

      final backup = {
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'outlet_id': outletId,
        'outlet': outlet == null
            ? null
            : {
                'id': outlet.id,
                'name': outlet.name,
                'address': outlet.address,
                'phone': outlet.phone,
                'receipt_header': outlet.receiptHeader,
                'receipt_footer': outlet.receiptFooter,
                'tax_percent': outlet.taxPercent,
                'service_charge_percent': outlet.serviceChargePercent,
              },
        'categories': allCategories
            .map((c) => {
                  'id': c.id,
                  'outlet_id': c.outletId,
                  'name': c.name,
                  'sort_order': c.sortOrder,
                  'color_hex': c.colorHex,
                  'is_active': c.isActive,
                  'updated_at': c.updatedAt.toIso8601String(),
                })
            .toList(),
        'products': allProducts
            .map((p) => {
                  'id': p.id,
                  'outlet_id': p.outletId,
                  'category_id': p.categoryId,
                  'name': p.name,
                  'price': p.price,
                  'cogs': p.cogs,
                  'image_url': p.imageUrl,
                  'description': p.description,
                  'is_available': p.isAvailable,
                  'track_stock': p.trackStock,
                  'stock': p.stock,
                  'updated_at': p.updatedAt.toIso8601String(),
                })
            .toList(),
        'orders': allOrders
            .map((o) => {
                  'id': o.id,
                  'outlet_id': o.outletId,
                  'order_number': o.orderNumber,
                  'type': o.type,
                  'status': o.status,
                  'cashier_id': o.cashierId,
                  'cashier_name': o.cashierName,
                  'total': o.total,
                  'payment_method': o.paymentMethod,
                  'paid_at': o.paidAt?.toIso8601String(),
                  'created_at': o.createdAt.toIso8601String(),
                })
            .toList(),
        'users': allUsers
            .map((u) => {
                  'id': u.id,
                  'outlet_id': u.outletId,
                  'name': u.name,
                  'pin': u.pin,
                  'role': u.role,
                  'is_active': u.isActive,
                })
            .toList(),
        'user_outlet_accesses': allAccesses
            .map((access) => {
                  'id': access.id,
                  'user_id': access.userId,
                  'outlet_id': access.outletId,
                  'created_at': access.createdAt.toIso8601String(),
                })
            .toList(),
        'tables': allTables
            .map((t) => {
                  'id': t.id,
                  'outlet_id': t.outletId,
                  'table_label': t.tableLabel,
                  'area': t.area,
                  'capacity': t.capacity,
                  'status': t.status,
                })
            .toList(),
      };

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final file =
          File('${dir.path}/sajia_backup_$timestamp.$_backupExtension');
      final encrypted = await _encryptBackupJson(
        jsonEncode(backup),
        passphrase.trim(),
      );
      await file.writeAsString(encrypted);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Backup ${AppBrand.name} - $timestamp',
        ),
      );

      return BackupResult.success;
    } catch (e) {
      debugPrint('[BackupService] backup error: $e');
      return BackupResult.error;
    }
  }

// ── RESTORE ────────────────────────────────────
  // ── BACKUP ────────────────────────────────────

  Future<BackupResult> restoreBackup(
    AppDatabase db, {
    String? filePath,
    String? passphrase,
  }) async {
    try {
      File file;

      if (filePath != null) {
        file = File(filePath);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final backupFiles = dir
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.contains('backup_') &&
                (f.path.endsWith('.$_backupExtension') ||
                    f.path.endsWith('.json')))
            .toList();

        if (backupFiles.isEmpty) return BackupResult.noBackupFound;

        backupFiles.sort((a, b) => b.path.compareTo(a.path));
        file = backupFiles.first;
      }

      if (!await file.exists()) return BackupResult.noBackupFound;

      final content = await file.readAsString();
      final decoded = await _decodeBackupContent(
        content,
        passphrase: passphrase?.trim(),
      );
      if (decoded.result != null) return decoded.result!;
      final data = decoded.data;

      if (data['version'] == null || data['outlet_id'] == null) {
        return BackupResult.invalidFile;
      }

      final outletId = data['outlet_id'] as String; // ← PENTING, harus di sini

      // Restore outlet
      if (data['outlet'] != null) {
        final o = data['outlet'] as Map<String, dynamic>;
        await (db.update(db.outlets)
              ..where((outlet) => outlet.id.equals(outletId)))
            .write(OutletsCompanion(
          name: Value(o['name'] as String),
          address: Value(o['address'] as String?),
          phone: Value(o['phone'] as String?),
          receiptHeader: Value(o['receipt_header'] as String?),
          receiptFooter: Value(o['receipt_footer'] as String?),
          taxPercent: Value(o['tax_percent'] as String? ?? '0'),
          serviceChargePercent:
              Value(o['service_charge_percent'] as String? ?? '0'),
        ));
      }

      // Restore categories
      for (final c in (data['categories'] as List)) {
        await db.productDao.upsertCategory(CategoriesCompanion(
          id: Value(c['id'] as String),
          outletId: Value(c['outlet_id'] as String),
          name: Value(c['name'] as String),
          sortOrder: Value(c['sort_order'] as int? ?? 0),
          colorHex: Value(c['color_hex'] as String? ?? '#888888'),
          isActive: Value(c['is_active'] as bool? ?? true),
          updatedAt: Value(DateTime.parse(c['updated_at'] as String)),
          isSynced: const Value(false),
        ));
      }

      // Restore products
      for (final p in (data['products'] as List)) {
        await db.productDao.upsertProduct(ProductsCompanion(
          id: Value(p['id'] as String),
          outletId: Value(p['outlet_id'] as String),
          categoryId: Value(p['category_id'] as String?),
          name: Value(p['name'] as String),
          price: Value(p['price'] as String),
          cogs: Value(p['cogs'] as String? ?? '0'),
          imageUrl: Value(p['image_url'] as String?),
          description: Value(p['description'] as String?),
          isAvailable: Value(p['is_available'] as bool? ?? true),
          trackStock: Value(p['track_stock'] as bool? ?? false),
          stock: Value(p['stock'] as String? ?? '0'),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ));
      }

      // Restore users
      for (final u in (data['users'] as List)) {
        await db.sessionDao.upsertUser(UsersCompanion(
          id: Value(u['id'] as String),
          outletId: Value(u['outlet_id'] as String),
          name: Value(u['name'] as String),
          pin: Value(u['pin'] as String),
          role: Value(u['role'] as String? ?? 'cashier'),
          isActive: Value(u['is_active'] as bool? ?? true),
          updatedAt: Value(DateTime.now()),
        ));
      }

      // Restore user outlet access
      for (final access in (data['user_outlet_accesses'] as List? ?? [])) {
        await db.into(db.userOutletAccesses).insert(
              UserOutletAccessesCompanion.insert(
                id: access['id'] as String,
                userId: access['user_id'] as String,
                outletId: access['outlet_id'] as String,
                createdAt: Value(DateTime.tryParse(
                      access['created_at'] as String? ?? '',
                    ) ??
                    DateTime.now()),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      // Restore tables
      for (final t in (data['tables'] as List)) {
        await db.orderDao.upsertTable(RestaurantTablesCompanion(
          id: Value(t['id'] as String),
          outletId: Value(t['outlet_id'] as String),
          tableLabel: Value(t['table_label'] as String),
          area: Value(t['area'] as String?),
          capacity: Value(t['capacity'] as int? ?? 4),
          status: const Value('available'),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ));
      }

      return BackupResult.success;
    } catch (e) {
      debugPrint('[BackupService] restore error: $e');
      return BackupResult.error;
    }
  }

  Future<String> _encryptBackupJson(String plainJson, String passphrase) async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = _deriveBackupKey(passphrase, salt);
    final encrypted = _encryptAesGcm(
      utf8.encode(plainJson),
      key: key,
      nonce: nonce,
    );
    final macStart = encrypted.length - 16;
    final cipherText = encrypted.sublist(0, macStart);
    final mac = encrypted.sublist(macStart);

    return jsonEncode({
      'format': _encryptedFormat,
      'version': _encryptedVersion,
      'created_at': DateTime.now().toIso8601String(),
      'kdf': {
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': _pbkdf2Iterations,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'algorithm': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'mac': base64Encode(mac),
        'ciphertext': base64Encode(cipherText),
      },
    });
  }

  Future<_DecodedBackup> _decodeBackupContent(
    String content, {
    String? passphrase,
  }) async {
    final parsed = jsonDecode(content);
    if (parsed is! Map<String, dynamic>) {
      return const _DecodedBackup.result(BackupResult.invalidFile);
    }

    if (parsed['format'] != _encryptedFormat) {
      return _DecodedBackup.data(parsed);
    }

    if (passphrase == null || passphrase.isEmpty) {
      return const _DecodedBackup.result(BackupResult.passwordRequired);
    }

    try {
      final kdf = parsed['kdf'] as Map<String, dynamic>?;
      final cipher = parsed['cipher'] as Map<String, dynamic>?;
      if (kdf == null || cipher == null) {
        return const _DecodedBackup.result(BackupResult.invalidFile);
      }

      final iterations = kdf['iterations'];
      if (iterations != _pbkdf2Iterations ||
          kdf['algorithm'] != 'pbkdf2-hmac-sha256' ||
          cipher['algorithm'] != 'aes-256-gcm') {
        return const _DecodedBackup.result(BackupResult.invalidFile);
      }

      final salt = base64Decode(kdf['salt'] as String);
      final key = _deriveBackupKey(passphrase, salt);
      final encrypted = Uint8List.fromList([
        base64Decode(cipher['ciphertext'] as String),
        base64Decode(cipher['mac'] as String),
      ].expand((bytes) => bytes).toList(growable: false));
      final plainBytes = _decryptAesGcm(
        encrypted,
        key: key,
        nonce: base64Decode(cipher['nonce'] as String),
      );
      final plain = jsonDecode(utf8.decode(plainBytes));
      if (plain is! Map<String, dynamic>) {
        return const _DecodedBackup.result(BackupResult.invalidFile);
      }
      return _DecodedBackup.data(plain);
    } on pc.InvalidCipherTextException {
      return const _DecodedBackup.result(BackupResult.wrongPassword);
    } on FormatException {
      return const _DecodedBackup.result(BackupResult.invalidFile);
    } catch (e) {
      debugPrint('[BackupService] decrypt backup error: $e');
      return const _DecodedBackup.result(BackupResult.wrongPassword);
    }
  }

  Uint8List _deriveBackupKey(
    String passphrase,
    List<int> salt,
  ) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(
        Uint8List.fromList(salt),
        _pbkdf2Iterations,
        32,
      ));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  Uint8List _encryptAesGcm(
    List<int> plainBytes, {
    required Uint8List key,
    required List<int> nonce,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(plainBytes));
  }

  Uint8List _decryptAesGcm(
    Uint8List encryptedBytes, {
    required Uint8List key,
    required List<int> nonce,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(key),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(encryptedBytes);
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

// ─────────────────────────────────────────────
// RESULT
// ─────────────────────────────────────────────

class _DecodedBackup {
  final Map<String, dynamic> data;
  final BackupResult? result;

  const _DecodedBackup.data(this.data) : result = null;
  const _DecodedBackup.result(this.result) : data = const {};
}

enum BackupResult {
  success,
  cancelled,
  invalidFile,
  noBackupFound,
  passwordRequired,
  passwordTooShort,
  wrongPassword,
  error,
}

extension BackupResultMessage on BackupResult {
  String get message {
    switch (this) {
      case BackupResult.success:
        return 'Berhasil';
      case BackupResult.cancelled:
        return 'Dibatalkan';
      case BackupResult.invalidFile:
        return 'File backup tidak valid';
      case BackupResult.noBackupFound:
        return 'Tidak ada file backup ditemukan';
      case BackupResult.passwordRequired:
        return 'Backup ini terenkripsi. Masukkan password backup';
      case BackupResult.passwordTooShort:
        return 'Password backup minimal 8 karakter';
      case BackupResult.wrongPassword:
        return 'Password backup salah atau file rusak';
      case BackupResult.error:
        return 'Terjadi kesalahan';
    }
  }
}

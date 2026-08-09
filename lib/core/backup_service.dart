import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _backupPasswordInitializedKey =
      'manual_backup_password_initialized_v1';

  Future<bool> hasInitializedBackupPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backupPasswordInitializedKey) ?? false;
  }

  Future<PickedBackup?> pickBackupFile() async {
    try {
      const backupType = XTypeGroup(
        label: 'Backup Sajia',
        extensions: [_backupExtension, 'json'],
      );
      final selection = await openFile(
        acceptedTypeGroups: const [backupType],
      );
      if (selection == null) return null;
      return PickedBackup(
        name: selection.name,
        content: await selection.readAsString(),
      );
    } catch (error, stackTrace) {
      debugPrint('[BackupService] file picker error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

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
      final orderIds = allOrders.map((order) => order.id).toList();
      final allOrderItems = orderIds.isEmpty
          ? <OrderItem>[]
          : await (db.select(db.orderItems)
                ..where((item) => item.orderId.isIn(orderIds)))
              .get();
      final productIds = allProducts.map((product) => product.id).toList();
      final allVariants = productIds.isEmpty
          ? <ProductVariant>[]
          : await (db.select(db.productVariants)
                ..where((variant) => variant.productId.isIn(productIds)))
              .get();
      final allUsers = await db.sessionDao.getUsers(outletId);
      final allAccesses = await (db.select(db.userOutletAccesses)
            ..where((access) => access.outletId.equals(outletId)))
          .get();
      final allTables = await (db.select(db.restaurantTables)
            ..where((t) => t.outletId.equals(outletId)))
          .get();
      final allSessions = await (db.select(db.sessions)
            ..where((session) => session.outletId.equals(outletId)))
          .get();
      final allExpenses = await (db.select(db.expenses)
            ..where((expense) => expense.outletId.equals(outletId)))
          .get();
      final outlet = await (db.select(db.outlets)
            ..where((o) => o.id.equals(outletId)))
          .getSingleOrNull();

      final backup = {
        'version': 2,
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
                  'low_stock_alert': p.lowStockAlert,
                  'sort_order': p.sortOrder,
                  'updated_at': p.updatedAt.toIso8601String(),
                })
            .toList(),
        'product_variants': allVariants
            .map((variant) => {
                  'id': variant.id,
                  'product_id': variant.productId,
                  'name': variant.name,
                  'options': variant.options,
                  'is_required': variant.isRequired,
                  'updated_at': variant.updatedAt.toIso8601String(),
                })
            .toList(),
        'orders': allOrders
            .map((o) => {
                  'id': o.id,
                  'outlet_id': o.outletId,
                  'order_number': o.orderNumber,
                  'type': o.type,
                  'status': o.status,
                  'table_id': o.tableId,
                  'table_label': o.tableLabel,
                  'cashier_id': o.cashierId,
                  'cashier_name': o.cashierName,
                  'customer_name': o.customerName,
                  'customer_count': o.customerCount,
                  'notes': o.notes,
                  'subtotal': o.subtotal,
                  'discount_amount': o.discountAmount,
                  'discount_percent': o.discountPercent,
                  'tax_amount': o.taxAmount,
                  'service_charge': o.serviceCharge,
                  'total': o.total,
                  'payment_method': o.paymentMethod,
                  'paid_amount': o.paidAmount,
                  'change_amount': o.changeAmount,
                  'payment_ref': o.paymentRef,
                  'paid_at': o.paidAt?.toIso8601String(),
                  'void_reason': o.voidReason,
                  'voided_by': o.voidedBy,
                  'created_at': o.createdAt.toIso8601String(),
                  'updated_at': o.updatedAt.toIso8601String(),
                })
            .toList(),
        'order_items': allOrderItems
            .map((item) => {
                  'id': item.id,
                  'order_id': item.orderId,
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'variant_summary': item.variantSummary,
                  'unit_price': item.unitPrice,
                  'unit_cogs': item.unitCogs,
                  'category_id': item.categoryId,
                  'category_name': item.categoryName,
                  'quantity': item.quantity,
                  'discount': item.discount,
                  'subtotal': item.subtotal,
                  'notes': item.notes,
                  'status': item.status,
                  'created_at': item.createdAt.toIso8601String(),
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
                  'created_at': u.createdAt.toIso8601String(),
                  'updated_at': u.updatedAt.toIso8601String(),
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
                  'current_order_id': t.currentOrderId,
                  'updated_at': t.updatedAt.toIso8601String(),
                })
            .toList(),
        'sessions': allSessions
            .map((session) => {
                  'id': session.id,
                  'outlet_id': session.outletId,
                  'cashier_id': session.cashierId,
                  'cashier_name': session.cashierName,
                  'opening_cash': session.openingCash,
                  'closing_cash': session.closingCash,
                  'total_cash_sales': session.totalCashSales,
                  'total_qris_sales': session.totalQrisSales,
                  'total_orders': session.totalOrders,
                  'total_voids': session.totalVoids,
                  'notes': session.notes,
                  'opened_at': session.openedAt.toIso8601String(),
                  'closed_at': session.closedAt?.toIso8601String(),
                })
            .toList(),
        'expenses': allExpenses
            .map((expense) => {
                  'id': expense.id,
                  'outlet_id': expense.outletId,
                  'category': expense.category,
                  'description': expense.description,
                  'amount': expense.amount,
                  'occurred_at': expense.occurredAt.toIso8601String(),
                  'created_at': expense.createdAt.toIso8601String(),
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
      final backupJson = jsonEncode(backup);
      final normalizedPassphrase = passphrase.trim();
      final encrypted = await compute(
        _encryptBackupInBackground,
        <String>[backupJson, normalizedPassphrase],
      );
      await file.writeAsString(encrypted);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_backupPasswordInitializedKey, true);

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
    String? fileContent,
    String? passphrase,
  }) async {
    try {
      late final String content;
      if (fileContent != null) {
        content = fileContent;
      } else {
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
        content = await file.readAsString();
      }

      final normalizedPassphrase = passphrase?.trim();
      final decoded = await compute(
        _decodeBackupInBackground,
        <String?>[content, normalizedPassphrase],
      );
      if (decoded.result != null) return decoded.result!;
      final data = decoded.data;

      if (data['version'] == null || data['outlet_id'] == null) {
        return BackupResult.invalidFile;
      }

      final outletId = data['outlet_id'] as String; // ← PENTING, harus di sini

      await db.transaction(() async {
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
            lowStockAlert: Value(p['low_stock_alert'] as String? ?? '5'),
            sortOrder: Value(p['sort_order'] as int? ?? 0),
            updatedAt: Value(
              DateTime.tryParse(p['updated_at'] as String? ?? '') ??
                  DateTime.now(),
            ),
            isSynced: const Value(false),
          ));
        }

        // Restore product variants/modifiers after their parent products.
        for (final variant in (data['product_variants'] as List? ?? [])) {
          await db.into(db.productVariants).insert(
                ProductVariantsCompanion(
                  id: Value(variant['id'] as String),
                  productId: Value(variant['product_id'] as String),
                  name: Value(variant['name'] as String),
                  options: Value(variant['options'] as String? ?? '[]'),
                  isRequired: Value(variant['is_required'] as bool? ?? false),
                  updatedAt: Value(
                    DateTime.tryParse(
                          variant['updated_at'] as String? ?? '',
                        ) ??
                        DateTime.now(),
                  ),
                  isSynced: const Value(false),
                ),
                mode: InsertMode.insertOrReplace,
              );
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
            createdAt: Value(
              DateTime.tryParse(u['created_at'] as String? ?? '') ??
                  DateTime.now(),
            ),
            updatedAt: Value(
              DateTime.tryParse(u['updated_at'] as String? ?? '') ??
                  DateTime.now(),
            ),
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
            status: Value(t['status'] as String? ?? 'available'),
            currentOrderId: Value(t['current_order_id'] as String?),
            updatedAt: Value(
              DateTime.tryParse(t['updated_at'] as String? ?? '') ??
                  DateTime.now(),
            ),
            isSynced: const Value(false),
          ));
        }

        // Restore transaction history before its items so reports and receipt
        // reprints remain available after a device migration.
        for (final o in (data['orders'] as List? ?? [])) {
          await db.into(db.orders).insert(
                OrdersCompanion(
                  id: Value(o['id'] as String),
                  outletId: Value(o['outlet_id'] as String),
                  orderNumber: Value(o['order_number'] as String),
                  type: Value(o['type'] as String? ?? 'takeaway'),
                  status: Value(o['status'] as String? ?? 'paid'),
                  tableId: Value(o['table_id'] as String?),
                  tableLabel: Value(o['table_label'] as String?),
                  cashierId: Value(o['cashier_id'] as String? ?? ''),
                  cashierName: Value(o['cashier_name'] as String? ?? ''),
                  customerName: Value(o['customer_name'] as String?),
                  customerCount: Value(o['customer_count'] as String?),
                  notes: Value(o['notes'] as String?),
                  subtotal: Value(
                      o['subtotal'] as String? ?? o['total'] as String? ?? '0'),
                  discountAmount: Value(o['discount_amount'] as String? ?? '0'),
                  discountPercent:
                      Value(o['discount_percent'] as String? ?? '0'),
                  taxAmount: Value(o['tax_amount'] as String? ?? '0'),
                  serviceCharge: Value(o['service_charge'] as String? ?? '0'),
                  total: Value(o['total'] as String? ?? '0'),
                  paymentMethod: Value(o['payment_method'] as String?),
                  paidAmount: Value(o['paid_amount'] as String?),
                  changeAmount: Value(o['change_amount'] as String?),
                  paymentRef: Value(o['payment_ref'] as String?),
                  paidAt:
                      Value(DateTime.tryParse(o['paid_at'] as String? ?? '')),
                  voidReason: Value(o['void_reason'] as String?),
                  voidedBy: Value(o['voided_by'] as String?),
                  createdAt: Value(
                    DateTime.tryParse(o['created_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  updatedAt: Value(
                    DateTime.tryParse(o['updated_at'] as String? ?? '') ??
                        DateTime.tryParse(o['created_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  isSynced: const Value(false),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        for (final item in (data['order_items'] as List? ?? [])) {
          await db.into(db.orderItems).insert(
                OrderItemsCompanion(
                  id: Value(item['id'] as String),
                  orderId: Value(item['order_id'] as String),
                  productId: Value(item['product_id'] as String),
                  productName: Value(item['product_name'] as String),
                  variantSummary: Value(item['variant_summary'] as String?),
                  unitPrice: Value(item['unit_price'] as String? ?? '0'),
                  unitCogs: Value(item['unit_cogs'] as String?),
                  categoryId: Value(item['category_id'] as String?),
                  categoryName: Value(item['category_name'] as String?),
                  quantity: Value(item['quantity'] as String? ?? '0'),
                  discount: Value(item['discount'] as String? ?? '0'),
                  subtotal: Value(item['subtotal'] as String? ?? '0'),
                  notes: Value(item['notes'] as String?),
                  status: Value(item['status'] as String? ?? 'pending'),
                  createdAt: Value(
                    DateTime.tryParse(item['created_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  isSynced: const Value(false),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        for (final session in (data['sessions'] as List? ?? [])) {
          await db.into(db.sessions).insert(
                SessionsCompanion(
                  id: Value(session['id'] as String),
                  outletId: Value(session['outlet_id'] as String),
                  cashierId: Value(session['cashier_id'] as String),
                  cashierName: Value(session['cashier_name'] as String),
                  openingCash: Value(session['opening_cash'] as String? ?? '0'),
                  closingCash: Value(session['closing_cash'] as String?),
                  totalCashSales:
                      Value(session['total_cash_sales'] as String? ?? '0'),
                  totalQrisSales:
                      Value(session['total_qris_sales'] as String? ?? '0'),
                  totalOrders: Value(session['total_orders'] as int? ?? 0),
                  totalVoids: Value(session['total_voids'] as int? ?? 0),
                  notes: Value(session['notes'] as String?),
                  openedAt: Value(
                    DateTime.tryParse(session['opened_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  closedAt: Value(
                    DateTime.tryParse(session['closed_at'] as String? ?? ''),
                  ),
                  isSynced: const Value(false),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        for (final expense in (data['expenses'] as List? ?? [])) {
          await db.into(db.expenses).insert(
                ExpensesCompanion(
                  id: Value(expense['id'] as String),
                  outletId: Value(expense['outlet_id'] as String),
                  category: Value(expense['category'] as String),
                  description: Value(expense['description'] as String?),
                  amount: Value(expense['amount'] as String? ?? '0'),
                  occurredAt: Value(
                    DateTime.tryParse(
                            expense['occurred_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  createdAt: Value(
                    DateTime.tryParse(expense['created_at'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  isSynced: const Value(false),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }
      });

      return BackupResult.success;
    } catch (e) {
      debugPrint('[BackupService] restore error: $e');
      return BackupResult.error;
    }
  }

  static String _encryptBackupJsonSync(
    String plainJson,
    String passphrase,
  ) {
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

  static _DecodedBackup _decodeBackupContentSync(
    String content, {
    String? passphrase,
  }) {
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

  static Uint8List _deriveBackupKey(
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

  static Uint8List _encryptAesGcm(
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

  static Uint8List _decryptAesGcm(
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

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

// ─────────────────────────────────────────────
// RESULT
// ─────────────────────────────────────────────

// These workers must stay top-level. A closure created inside restoreBackup can
// capture the Drift/SQLite connection and crash when Dart tries to send that
// native object to another isolate.
String _encryptBackupInBackground(List<String> arguments) {
  return BackupService._encryptBackupJsonSync(arguments[0], arguments[1]);
}

_DecodedBackup _decodeBackupInBackground(List<String?> arguments) {
  return BackupService._decodeBackupContentSync(
    arguments[0]!,
    passphrase: arguments[1],
  );
}

class PickedBackup {
  final String name;
  final String content;

  const PickedBackup({required this.name, required this.content});
}

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

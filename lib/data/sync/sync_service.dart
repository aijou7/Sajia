import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show InsertMode, OrderingTerm, Value;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';
import 'product_image_uploader.dart';

class SyncService {
  static const isEnabled = bool.fromEnvironment(
    'ENABLE_CLOUD_SYNC',
    defaultValue: true,
  );

  final AppDatabase _db;
  final SupabaseClient _supabase;
  StreamSubscription? _connectivitySub;
  Timer? _periodicSync;
  bool _isSyncing = false;
  final Set<String>? Function()? _operationalOutletScope;
  bool _strictRecoveryPull = false;
  bool _recoveryPullFailed = false;

  SyncService(
    this._db,
    this._supabase, {
    Set<String>? Function()? operationalOutletScope,
  }) : _operationalOutletScope = operationalOutletScope;

  void start() {
    if (!isEnabled) {
      debugPrint('[SyncService] Cloud sync disabled by build config');
      return;
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasConnection(results)) syncAll();
    });
    _periodicSync ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => syncAll(),
    );
    syncAll();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicSync?.cancel();
  }

  Future<void> syncAll() async {
    if (!isEnabled) return;
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final connected = await _isConnected();
      if (!connected) return;
      if (_supabase.auth.currentUser?.email == null) return;

      // Account recovery data is backed up for every verified owner. This is
      // what allows a replacement device to restore the original owner PIN,
      // staff PINs, outlets, menu, variants, and tables without creating a
      // duplicate local identity.
      await _pushRecoveryData();
      final outletIds = await _pullRecoveryData();

      // Transaction history, shifts, expenses, and cross-device live sync
      // remain part of the Cloud entitlement.
      final cloudOutletIds = await _cloudEntitledOutletIds();
      final scopedCloudOutletIds = _scopeOperationalOutlets(cloudOutletIds);
      if (scopedCloudOutletIds.isEmpty) {
        debugPrint(
          '[SyncService] Recovery data synced; operational Cloud sync skipped',
        );
        return;
      }
      await _pushOperationalData(scopedCloudOutletIds);
      await _pullOperationalData(
        outletIds.where(scopedCloudOutletIds.contains).toList(),
      );
    } catch (e) {
      debugPrint('[SyncService] syncAll error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> pullAllForLogin(String outletId) async {
    try {
      final connected = await _isConnected();
      if (!connected) return false;
      if (_supabase.auth.currentUser?.email == null) return false;

      // Explicit device recovery must work even when a build was produced
      // with background cloud sync disabled.
      _strictRecoveryPull = true;
      _recoveryPullFailed = false;
      final outletIds = await _pullRecoveryData(seedOutletId: outletId);
      if (_recoveryPullFailed || outletIds.isEmpty) return false;

      final cloudOutletIds = await _cloudEntitledOutletIds();
      final entitledOutlets = outletIds.where(cloudOutletIds.contains).toList();
      if (entitledOutlets.isNotEmpty) {
        await _pullOperationalData(entitledOutlets);
      }
      return !_recoveryPullFailed;
    } catch (e) {
      debugPrint('[SyncService] pullAllForLogin error: $e');
      return false;
    } finally {
      _strictRecoveryPull = false;
    }
  }

  Future<void> _pushRecoveryData() async {
    final localOutlets = await _db.select(_db.outlets).get();
    await _pullTombstones(localOutlets.map((outlet) => outlet.id).toList());
    await _processPendingRecoveryDeletes();
    await _pushOutlets();
    await _pushUsers();
    await _pushUserOutletAccesses();
    await _pushCategories();
    await _pushProducts();
    await _pushProductVariants();
    await _pushTables();
  }

  Future<void> _pushOperationalData(Set<String> outletIds) async {
    await _processPendingOperationalDeletes(outletIds);
    await _pushOrders(outletIds);
    await _pushOrderItems(outletIds);
    await _processPendingInventoryEvents(outletIds);
    await _pushSessions(outletIds);
    await _pushExpenses(outletIds);
  }

  Future<void> _processPendingRecoveryDeletes() async {
    final pending = await _db.syncDao.getPending(limit: 100);
    for (final item in pending) {
      if (item.operation != 'delete') continue;
      if (item.syncTableName != 'products' &&
          item.syncTableName != 'product_variants' &&
          item.syncTableName != 'restaurant_tables' &&
          item.syncTableName != 'user_outlet_accesses') {
        continue;
      }

      try {
        if (item.syncTableName == 'products') {
          final payload = _decodePayload(item.payload);
          var outletId = payload['outlet_id'] as String?;
          if (outletId == null) {
            final remote = await _supabase
                .from('products')
                .select('outlet_id')
                .eq('id', item.recordId)
                .maybeSingle();
            outletId = remote?['outlet_id'] as String?;
          }
          if (outletId != null) {
            await _recordTombstone(
              outletId: outletId,
              entityType: 'product',
              recordId: item.recordId,
            );
          }
          // Hapus varian lebih dulu agar tidak tertahan foreign key Supabase.
          await _supabase
              .from('product_variants')
              .delete()
              .eq('product_id', item.recordId);
          await _supabase.from('products').delete().eq('id', item.recordId);
        } else if (item.syncTableName == 'product_variants') {
          await _supabase
              .from('product_variants')
              .delete()
              .eq('id', item.recordId);
        } else if (item.syncTableName == 'restaurant_tables') {
          final payload = _decodePayload(item.payload);
          var outletId = payload['outlet_id'] as String?;
          if (outletId == null) {
            final remote = await _supabase
                .from('restaurant_tables')
                .select('outlet_id')
                .eq('id', item.recordId)
                .maybeSingle();
            outletId = remote?['outlet_id'] as String?;
          }
          if (outletId == null) {
            throw StateError('Outlet meja tidak ditemukan');
          }
          await _recordTombstone(
            outletId: outletId,
            entityType: 'restaurant_table',
            recordId: item.recordId,
          );
          await _supabase
              .from('restaurant_tables')
              .delete()
              .eq('id', item.recordId);
        } else if (item.syncTableName == 'user_outlet_accesses') {
          final payload = _decodePayload(item.payload);
          var outletId = payload['outlet_id'] as String?;
          if (outletId == null) {
            final remote = await _supabase
                .from('user_outlet_accesses')
                .select('outlet_id')
                .eq('id', item.recordId)
                .maybeSingle();
            outletId = remote?['outlet_id'] as String?;
          }
          if (outletId == null) {
            throw StateError('Outlet penugasan tidak ditemukan');
          }
          await _recordTombstone(
            outletId: outletId,
            entityType: 'user_outlet_access',
            recordId: item.recordId,
          );
          await _supabase
              .from('user_outlet_accesses')
              .delete()
              .eq('id', item.recordId);
        }
        await _db.syncDao.markDone(item.id);
      } catch (e) {
        await _db.syncDao.incrementRetry(item.id, e.toString());
        debugPrint(
          '[SyncService] delete ${item.syncTableName} ${item.recordId} failed: $e',
        );
      }
    }
  }

  Future<void> _processPendingOperationalDeletes(Set<String> outletIds) async {
    final pending = await _db.syncDao.getPending(limit: 100);
    for (final item in pending) {
      if (item.operation != 'delete' || item.syncTableName != 'expenses') {
        continue;
      }

      try {
        final payload = _decodePayload(item.payload);
        final outletId = payload['outlet_id'] as String?;
        if (outletId == null || !outletIds.contains(outletId)) continue;
        await _recordTombstone(
          outletId: outletId,
          entityType: 'expense',
          recordId: item.recordId,
        );
        await _supabase.from('expenses').delete().eq('id', item.recordId);
        await _db.syncDao.markDone(item.id);
      } catch (e) {
        await _db.syncDao.incrementRetry(item.id, e.toString());
        debugPrint(
          '[SyncService] delete expense ${item.recordId} failed: $e',
        );
      }
    }
  }

  Set<String> _scopeOperationalOutlets(Set<String> cloudOutletIds) {
    final requestedScope = _operationalOutletScope?.call();
    if (requestedScope == null) return cloudOutletIds;
    return cloudOutletIds.intersection(requestedScope);
  }

  void _markRecoveryPullFailed() {
    if (_strictRecoveryPull) _recoveryPullFailed = true;
  }

  Future<List<String>> _pullRecoveryData({String? seedOutletId}) async {
    final outletIds = await _pullAccessibleOutlets(seedOutletId: seedOutletId);
    await _pullTombstones(outletIds);
    await _pullUserOutletAccesses();
    for (final outletId in outletIds) {
      await _pullUsers(outletId);
      await _pullTables(outletId);
    }
    await _pullCategories();
    await _pullProducts();
    await _pullProductVariants();
    // A remote delete can leave the source row temporarily visible if the
    // tombstone write succeeded but deleting the source table is being
    // retried. Apply tombstones once more after all recovery pulls so such a
    // row cannot reappear locally in that window.
    await _pullTombstones(outletIds);
    return outletIds;
  }

  Future<void> _pullOperationalData(List<String> outletIds) async {
    for (final outletId in outletIds) {
      await _pullOrders(outletId);
      await _pullSessions(outletId);
    }
    await _pullOrderItems();
    await _pullExpenses(outletIds);
    await _pullProducts();
  }

  Future<void> _recordTombstone({
    required String outletId,
    required String entityType,
    required String recordId,
  }) async {
    await _supabase.from('sync_tombstones').upsert({
      'outlet_id': outletId,
      'entity_type': entityType,
      'record_id': recordId,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'entity_type,record_id');
  }

  Future<void> _pullTombstones(List<String> outletIds) async {
    for (final outletId in outletIds.toSet()) {
      try {
        final response = await _supabase
            .from('sync_tombstones')
            .select('entity_type,record_id,deleted_at')
            .eq('outlet_id', outletId);
        for (final row in response as List? ?? const []) {
          final map = _asMap(row);
          final recordId = map['record_id'] as String?;
          if (recordId == null) continue;
          switch (map['entity_type']) {
            case 'product':
              await _db.productDao.deleteProduct(recordId);
            case 'expense':
              await _db.financeDao.deleteExpense(recordId);
            case 'restaurant_table':
              await _db.orderDao.deleteTable(recordId, enqueueSync: false);
            case 'user_outlet_access':
              final deletedAt = _date(map['deleted_at']);
              final local = await (_db.select(_db.userOutletAccesses)
                    ..where((access) => access.id.equals(recordId)))
                  .getSingleOrNull();
              // A newer local row means the owner deliberately restored the
              // assignment after the deletion. It will supersede and clear
              // the old tombstone when pushed.
              if (local == null ||
                  deletedAt == null ||
                  !local.createdAt.isAfter(deletedAt)) {
                await _db.sessionDao.deleteUserOutletAccess(
                  recordId,
                  enqueueSync: false,
                );
              }
          }
        }
      } catch (e) {
        _markRecoveryPullFailed();
        debugPrint('[SyncService] pull tombstones for $outletId failed: $e');
      }
    }
  }

  Future<List<String>> _pullAccessibleOutlets({String? seedOutletId}) async {
    final pulled = <String>{};
    try {
      final response = await _supabase.rpc('get_authenticated_owner_outlets');
      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _upsertOutletFromMap(map);
        final id = map['id'] as String?;
        if (id != null) pulled.add(id);
      }
    } catch (e) {
      debugPrint('[SyncService] owner outlet rpc unavailable: $e');
    }

    if (seedOutletId != null && !pulled.contains(seedOutletId)) {
      if (await _pullOutlet(seedOutletId)) pulled.add(seedOutletId);
    }

    if (pulled.isEmpty) {
      try {
        final response = await _supabase.from('outlets').select();
        for (final row in response as List? ?? const []) {
          final map = _asMap(row);
          await _upsertOutletFromMap(map);
          final id = map['id'] as String?;
          if (id != null) pulled.add(id);
        }
      } catch (e) {
        _markRecoveryPullFailed();
        debugPrint('[SyncService] pull all outlets failed: $e');
      }
    }

    if (pulled.isEmpty) {
      _markRecoveryPullFailed();
      if (_strictRecoveryPull) return const [];
      final local = await (_db.select(_db.outlets)
            ..orderBy([(outlet) => OrderingTerm.asc(outlet.createdAt)]))
          .get();
      pulled.addAll(local.map((outlet) => outlet.id));
    }

    return pulled.toList();
  }

  Future<bool> _pullOutlet(String outletId) async {
    try {
      final response =
          await _supabase.from('outlets').select().eq('id', outletId).single();
      await _upsertOutletFromMap(_asMap(response));
      return true;
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull outlet $outletId failed: $e');
      return false;
    }
  }

  Future<void> _upsertOutletFromMap(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    final name = row['name'] as String?;
    if (id == null || name == null) return;
    await _db.into(_db.outlets).insertOnConflictUpdate(
          OutletsCompanion.insert(
            id: id,
            name: name,
            address: Value(row['address'] as String?),
            phone: Value(row['phone'] as String?),
            taxPercent: Value(row['tax_percent']?.toString() ?? '0'),
            serviceChargePercent:
                Value(row['service_charge_percent']?.toString() ?? '0'),
            receiptHeader: Value(row['receipt_header'] as String?),
            receiptFooter: Value(row['receipt_footer'] as String?),
            licenseKey: row['license_key'] as String? ?? 'FREE',
            licenseExpiry: Value(_date(row['license_expiry'])),
            cloudExpiry: Value(_date(row['cloud_expiry'])),
            createdAt: Value(_date(row['created_at']) ?? DateTime.now()),
          ),
        );
  }

  Future<void> _pullUsers(String outletId) async {
    try {
      final response =
          await _supabase.from('users').select().eq('outlet_id', outletId);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.sessionDao.upsertUser(UsersCompanion(
          id: Value(map['id'] as String),
          outletId: Value(map['outlet_id'] as String),
          name: Value(map['name'] as String),
          pin: Value(map['pin'] as String),
          role: Value(map['role'] as String? ?? 'cashier'),
          isActive: Value(map['is_active'] as bool? ?? true),
          updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull users failed: $e');
    }
  }

  Future<void> _pullUserOutletAccesses() async {
    try {
      final response = await _supabase.from('user_outlet_accesses').select();
      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.into(_db.userOutletAccesses).insert(
              UserOutletAccessesCompanion.insert(
                id: map['id'] as String,
                userId: map['user_id'] as String,
                outletId: map['outlet_id'] as String,
                createdAt: Value(_date(map['created_at']) ?? DateTime.now()),
                isSynced: const Value(true),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull user outlet access failed: $e');
    }
  }

  Future<void> _pullTables(String outletId) async {
    try {
      final response = await _supabase
          .from('restaurant_tables')
          .select()
          .eq('outlet_id', outletId);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.orderDao.upsertTable(RestaurantTablesCompanion(
          id: Value(map['id'] as String),
          outletId: Value(map['outlet_id'] as String),
          tableLabel: Value(map['table_label'] as String),
          area: Value(map['area'] as String?),
          capacity: Value(map['capacity'] as int? ?? 4),
          status: Value(map['status'] as String? ?? 'available'),
          currentOrderId: Value(map['current_order_id'] as String?),
          updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull tables failed: $e');
    }
  }

  Future<void> _pullOrders(String outletId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('outlet_id', outletId)
          .order('created_at', ascending: false)
          .limit(500);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.into(_db.orders).insertOnConflictUpdate(OrdersCompanion(
              id: Value(map['id'] as String),
              outletId: Value(map['outlet_id'] as String),
              orderNumber: Value(map['order_number'] as String),
              type: Value(map['type'] as String? ?? 'dine_in'),
              status: Value(map['status'] as String? ?? 'paid'),
              tableId: Value(map['table_id'] as String?),
              tableLabel: Value(map['table_label'] as String?),
              cashierId: Value(map['cashier_id'] as String? ?? ''),
              cashierName: Value(map['cashier_name'] as String? ?? ''),
              customerName: Value(map['customer_name'] as String?),
              customerCount: Value(map['customer_count']?.toString()),
              notes: Value(map['notes'] as String?),
              subtotal: Value(map['subtotal']?.toString() ?? '0'),
              discountAmount: Value(map['discount_amount']?.toString() ?? '0'),
              discountPercent:
                  Value(map['discount_percent']?.toString() ?? '0'),
              taxAmount: Value(map['tax_amount']?.toString() ?? '0'),
              serviceCharge: Value(map['service_charge']?.toString() ?? '0'),
              total: Value(map['total']?.toString() ?? '0'),
              paymentMethod: Value(map['payment_method'] as String?),
              paidAmount: Value(map['paid_amount']?.toString()),
              changeAmount: Value(map['change_amount']?.toString()),
              paymentRef: Value(map['payment_ref'] as String?),
              paidAt: Value(_date(map['paid_at'])),
              voidReason: Value(map['void_reason'] as String?),
              voidedBy: Value(map['voided_by'] as String?),
              createdAt: Value(_date(map['created_at']) ?? DateTime.now()),
              updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
              isSynced: const Value(true),
            ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull orders failed: $e');
    }
  }

  Future<void> _pullOrderItems() async {
    try {
      final response = await _supabase
          .from('order_items')
          .select()
          .order('created_at', ascending: false)
          .limit(2000);
      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.orderDao.upsertOrderItem(OrderItemsCompanion(
          id: Value(map['id'] as String),
          orderId: Value(map['order_id'] as String),
          productId: Value(map['product_id'] as String),
          productName: Value(map['product_name'] as String),
          variantSummary: Value(map['variant_summary'] as String?),
          unitPrice: Value(map['unit_price']?.toString() ?? '0'),
          unitCogs: Value(map['unit_cogs']?.toString()),
          categoryId: Value(map['category_id'] as String?),
          categoryName: Value(map['category_name'] as String?),
          quantity: Value(map['quantity']?.toString() ?? '0'),
          discount: Value(map['discount']?.toString() ?? '0'),
          subtotal: Value(map['subtotal']?.toString() ?? '0'),
          notes: Value(map['notes'] as String?),
          status: Value(map['status'] as String? ?? 'pending'),
          createdAt: Value(_date(map['created_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull order items failed: $e');
    }
  }

  Future<void> _pullProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .order('updated_at', ascending: false)
          .limit(1000);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.productDao.upsertProduct(ProductsCompanion(
          id: Value(map['id'] as String),
          outletId: Value(map['outlet_id'] as String),
          categoryId: Value(map['category_id'] as String?),
          name: Value(map['name'] as String),
          price: Value(map['price'].toString()),
          cogs: Value(map['cogs']?.toString() ?? '0'),
          imageUrl: Value(map['image_url'] as String?),
          description: Value(map['description'] as String?),
          isAvailable: Value(map['is_available'] as bool? ?? true),
          trackStock: Value(map['track_stock'] as bool? ?? false),
          stock: Value(map['stock']?.toString() ?? '0'),
          lowStockAlert: Value(map['low_stock_alert']?.toString() ?? '5'),
          sortOrder: Value(map['sort_order'] as int? ?? 0),
          updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull products failed: $e');
    }
  }

  Future<void> _pullProductVariants() async {
    try {
      final response = await _supabase
          .from('product_variants')
          .select()
          .order('updated_at', ascending: false)
          .limit(2000);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        final options = map['options'];
        await _db.productDao.upsertVariant(ProductVariantsCompanion(
          id: Value(map['id'] as String),
          productId: Value(map['product_id'] as String),
          name: Value(map['name'] as String),
          options: Value(
            options is String ? options : jsonEncode(options ?? const []),
          ),
          isRequired: Value(map['is_required'] as bool? ?? false),
          updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull product variants failed: $e');
    }
  }

  Future<void> _pullCategories() async {
    try {
      final response =
          await _supabase.from('categories').select().order('sort_order');

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.productDao.upsertCategory(CategoriesCompanion(
          id: Value(map['id'] as String),
          outletId: Value(map['outlet_id'] as String),
          name: Value(map['name'] as String),
          sortOrder: Value(map['sort_order'] as int? ?? 0),
          colorHex: Value(map['color_hex'] as String? ?? '#888888'),
          isActive: Value(map['is_active'] as bool? ?? true),
          updatedAt: Value(_date(map['updated_at']) ?? DateTime.now()),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull categories failed: $e');
    }
  }

  Future<void> _pullExpenses(List<String> outletIds) async {
    if (outletIds.isEmpty) return;
    try {
      for (final outletId in outletIds) {
        final response =
            await _supabase.from('expenses').select().eq('outlet_id', outletId);
        for (final row in response as List? ?? const []) {
          final map = _asMap(row);
          await _db.financeDao.upsertExpense(ExpensesCompanion(
            id: Value(map['id'] as String),
            outletId: Value(map['outlet_id'] as String),
            category: Value(map['category'] as String? ?? 'Operasional'),
            description: Value(map['description'] as String?),
            amount: Value(map['amount']?.toString() ?? '0'),
            occurredAt: Value(_date(map['occurred_at']) ?? DateTime.now()),
            createdAt: Value(_date(map['created_at']) ?? DateTime.now()),
            isSynced: const Value(true),
          ));
        }
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull expenses failed: $e');
    }
  }

  Future<void> _pullSessions(String outletId) async {
    try {
      final response = await _supabase
          .from('sessions')
          .select()
          .eq('outlet_id', outletId)
          .order('opened_at', ascending: false)
          .limit(500);

      for (final row in response as List? ?? const []) {
        final map = _asMap(row);
        await _db.into(_db.sessions).insertOnConflictUpdate(
              SessionsCompanion(
                id: Value(map['id'] as String),
                outletId: Value(map['outlet_id'] as String),
                cashierId: Value(map['cashier_id'] as String),
                cashierName: Value(map['cashier_name'] as String),
                openingCash: Value(map['opening_cash']?.toString() ?? '0'),
                closingCash: Value(map['closing_cash']?.toString()),
                totalCashSales:
                    Value(map['total_cash_sales']?.toString() ?? '0'),
                totalQrisSales:
                    Value(map['total_qris_sales']?.toString() ?? '0'),
                totalOrders: Value(map['total_orders'] as int? ?? 0),
                totalVoids: Value(map['total_voids'] as int? ?? 0),
                notes: Value(map['notes'] as String?),
                openedAt: Value(_date(map['opened_at']) ?? DateTime.now()),
                closedAt: Value(_date(map['closed_at'])),
                isSynced: const Value(true),
              ),
            );
      }
    } catch (e) {
      _markRecoveryPullFailed();
      debugPrint('[SyncService] pull sessions failed: $e');
    }
  }

  Future<void> _pushOutlets() async {
    final rows = await _db.select(_db.outlets).get();
    final ownerEmail = _supabase.auth.currentUser?.email;
    for (final outlet in rows) {
      try {
        // License fields are server-owned. Never push local license_key,
        // license_expiry, or cloud_expiry from the APK because a modified app
        // or edited local DB could otherwise promote itself to Pro/Cloud.
        //
        // Only Edge Functions/webhooks with the service role may update plan
        // entitlements after a verified payment.
        await _supabase.from('outlets').upsert({
          'id': outlet.id,
          'name': outlet.name,
          if (ownerEmail != null) 'owner_email': ownerEmail,
          'address': outlet.address,
          'phone': outlet.phone,
          'tax_percent': outlet.taxPercent,
          'service_charge_percent': outlet.serviceChargePercent,
          'receipt_header': outlet.receiptHeader,
          'receipt_footer': outlet.receiptFooter,
          'created_at': outlet.createdAt.toUtc().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[SyncService] push outlet ${outlet.id} failed: $e');
      }
    }
  }

  Future<void> _pushUsers() async {
    final unsynced = await _db.sessionDao.getUnsyncedUsers();
    for (final user in unsynced) {
      try {
        await _supabase.from('users').upsert({
          'id': user.id,
          'outlet_id': user.outletId,
          'name': user.name,
          'pin': user.pin,
          'role': user.role,
          'is_active': user.isActive,
          'updated_at': user.updatedAt.toUtc().toIso8601String(),
        });
        await _db.sessionDao.markUserSynced(user.id);
      } catch (e) {
        debugPrint('[SyncService] push user ${user.id} failed: $e');
      }
    }
  }

  Future<void> _pushUserOutletAccesses() async {
    final unsynced = await _db.sessionDao.getUnsyncedUserOutletAccesses();
    for (final access in unsynced) {
      try {
        final tombstone = await _supabase
            .from('sync_tombstones')
            .select('deleted_at')
            .eq('entity_type', 'user_outlet_access')
            .eq('record_id', access.id)
            .maybeSingle();
        final deletedAt = _date(tombstone?['deleted_at']);
        if (deletedAt != null && !access.createdAt.isAfter(deletedAt)) {
          // The server deletion is newer than this local relationship. Drop
          // the stale copy instead of letting an old device recreate it.
          await _db.sessionDao.deleteUserOutletAccess(
            access.id,
            enqueueSync: false,
          );
          continue;
        }

        await _supabase.from('user_outlet_accesses').upsert({
          'id': access.id,
          'user_id': access.userId,
          'outlet_id': access.outletId,
          'created_at': access.createdAt.toUtc().toIso8601String(),
        });
        if (tombstone != null) {
          await _supabase
              .from('sync_tombstones')
              .delete()
              .eq('entity_type', 'user_outlet_access')
              .eq('record_id', access.id);
        }
        await _db.sessionDao.markUserOutletAccessSynced(access.id);
      } catch (e) {
        debugPrint(
            '[SyncService] push user outlet access ${access.id} failed: $e');
      }
    }
  }

  Future<void> _pushProducts() async {
    final unsynced = await _db.productDao.getUnsyncedProducts();
    for (final p in unsynced) {
      try {
        final remote = await _supabase
            .from('products')
            .select('id')
            .eq('id', p.id)
            .maybeSingle();
        final uploadedImage = await uploadProductImage(
          client: _supabase,
          outletId: p.outletId,
          productId: p.id,
          source: p.imageUrl,
        );
        await _supabase.from('products').upsert({
          'id': p.id,
          'outlet_id': p.outletId,
          'category_id': p.categoryId,
          'name': p.name,
          'description': p.description,
          'price': p.price,
          'cogs': p.cogs,
          'image_url': uploadedImage,
          'is_available': p.isAvailable,
          'track_stock': p.trackStock,
          // Stock changes are replayed as ordered, idempotent inventory events.
          // A new row starts at zero so an offline sale cannot be decremented twice.
          if (remote == null) 'stock': '0',
          'low_stock_alert': p.lowStockAlert,
          'sort_order': p.sortOrder,
          'updated_at': p.updatedAt.toUtc().toIso8601String(),
        });
        if (uploadedImage != p.imageUrl) {
          await (_db.update(_db.products)..where((row) => row.id.equals(p.id)))
              .write(ProductsCompanion(imageUrl: Value(uploadedImage)));
        }
        await _db.productDao.markProductSynced(p.id);
      } catch (e) {
        debugPrint('[SyncService] push product ${p.id} failed: $e');
      }
    }
  }

  Future<void> _processPendingInventoryEvents(Set<String> outletIds) async {
    final pending = await _db.syncDao.getPending(limit: 500);
    for (final item in pending) {
      if (item.syncTableName != 'stock_sets' &&
          item.syncTableName != 'stock_sales' &&
          item.syncTableName != 'stock_reversals') {
        continue;
      }
      try {
        final payload = _decodePayload(item.payload);
        final outletId = payload['outlet_id'] as String?;
        if (outletId == null || !outletIds.contains(outletId)) continue;
        if (item.syncTableName == 'stock_sets') {
          final stock = payload['stock'];
          if (stock is! num) throw const FormatException('Stok tidak valid');
          await _supabase.rpc('set_product_stock', params: {
            'p_product_id': item.recordId,
            'p_stock': stock,
          });
        } else {
          // Never mark an inventory event applied before every order item has
          // reached Postgres. Otherwise a transient item upload failure could
          // permanently apply only part of a sale.
          final unsyncedItems = await _db.orderDao.getUnsyncedItems();
          if (unsyncedItems.any((row) => row.orderId == item.recordId)) {
            continue;
          }
          if (item.syncTableName == 'stock_reversals') {
            await _supabase.rpc('reverse_order_stock_sale', params: {
              'p_order_id': item.recordId,
            });
          } else {
            await _supabase.rpc('apply_order_stock_sale', params: {
              'p_order_id': item.recordId,
            });
          }
        }
        await _db.syncDao.markDone(item.id);
      } catch (e) {
        await _db.syncDao.incrementRetry(item.id, e.toString());
        debugPrint(
          '[SyncService] inventory ${item.syncTableName} ${item.recordId} failed: $e',
        );
      }
    }
  }

  Future<void> _pushProductVariants() async {
    final unsynced = await _db.productDao.getUnsyncedVariants();
    for (final variant in unsynced) {
      try {
        dynamic options;
        try {
          options = jsonDecode(variant.options);
        } catch (_) {
          options = <String>[variant.options];
        }
        await _supabase.from('product_variants').upsert({
          'id': variant.id,
          'product_id': variant.productId,
          'name': variant.name,
          'options': options,
          'is_required': variant.isRequired,
          'updated_at': variant.updatedAt.toUtc().toIso8601String(),
        });
        await _db.productDao.markVariantSynced(variant.id);
      } catch (e) {
        debugPrint(
          '[SyncService] push product variant ${variant.id} failed: $e',
        );
      }
    }
  }

  Future<void> _pushCategories() async {
    final unsynced = await _db.productDao.getUnsyncedCategories();
    for (final c in unsynced) {
      try {
        await _supabase.from('categories').upsert({
          'id': c.id,
          'outlet_id': c.outletId,
          'name': c.name,
          'sort_order': c.sortOrder,
          'color_hex': c.colorHex,
          'is_active': c.isActive,
          'updated_at': c.updatedAt.toUtc().toIso8601String(),
        });
        await _db.productDao.markCategorySynced(c.id);
      } catch (e) {
        debugPrint('[SyncService] push category ${c.id} failed: $e');
      }
    }
  }

  Future<void> _pushTables() async {
    final unsynced = await _db.orderDao.getUnsyncedTables();
    for (final table in unsynced) {
      try {
        await _supabase.from('restaurant_tables').upsert({
          'id': table.id,
          'outlet_id': table.outletId,
          'table_label': table.tableLabel,
          'area': table.area,
          'capacity': table.capacity,
          'status': table.status,
          'current_order_id': table.currentOrderId,
          'updated_at': table.updatedAt.toUtc().toIso8601String(),
        });
        await _db.orderDao.markTableSynced(table.id);
      } catch (e) {
        debugPrint('[SyncService] push table ${table.id} failed: $e');
      }
    }
  }

  Future<void> _pushOrders(Set<String> outletIds) async {
    final unsynced = await _db.orderDao.getUnsyncedOrders();
    for (final o in unsynced) {
      if (!outletIds.contains(o.outletId)) continue;
      try {
        await _supabase.from('orders').upsert({
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
          'paid_at': o.paidAt?.toUtc().toIso8601String(),
          'void_reason': o.voidReason,
          'voided_by': o.voidedBy,
          'created_at': o.createdAt.toUtc().toIso8601String(),
          'updated_at': o.updatedAt.toUtc().toIso8601String(),
        });
        await _db.orderDao.markOrderSynced(o.id);
      } catch (e) {
        debugPrint('[SyncService] push order ${o.id} failed: $e');
      }
    }
  }

  Future<void> _pushOrderItems(Set<String> outletIds) async {
    final unsynced = await _db.orderDao.getUnsyncedItems();
    for (final item in unsynced) {
      final parent = await _db.orderDao.getOrder(item.orderId);
      if (parent == null || !outletIds.contains(parent.outletId)) continue;
      try {
        await _supabase.from('order_items').upsert({
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
          'created_at': item.createdAt.toUtc().toIso8601String(),
        });
        await _db.orderDao.markItemSynced(item.id);
      } catch (e) {
        debugPrint('[SyncService] push order item ${item.id} failed: $e');
      }
    }
  }

  Future<void> _pushSessions(Set<String> outletIds) async {
    final unsynced = await _db.sessionDao.getUnsyncedSessions();
    for (final s in unsynced) {
      if (!outletIds.contains(s.outletId)) continue;
      try {
        await _supabase.from('sessions').upsert({
          'id': s.id,
          'outlet_id': s.outletId,
          'cashier_id': s.cashierId,
          'cashier_name': s.cashierName,
          'opening_cash': s.openingCash,
          'closing_cash': s.closingCash,
          'total_cash_sales': s.totalCashSales,
          'total_qris_sales': s.totalQrisSales,
          'total_orders': s.totalOrders,
          'total_voids': s.totalVoids,
          'notes': s.notes,
          'opened_at': s.openedAt.toUtc().toIso8601String(),
          'closed_at': s.closedAt?.toUtc().toIso8601String(),
        });
        await _db.sessionDao.markSessionSynced(s.id);
      } catch (e) {
        debugPrint('[SyncService] push session ${s.id} failed: $e');
      }
    }
  }

  Future<void> _pushExpenses(Set<String> outletIds) async {
    final unsynced = await _db.financeDao.getUnsyncedExpenses();
    for (final expense in unsynced) {
      if (!outletIds.contains(expense.outletId)) continue;
      try {
        await _supabase.from('expenses').upsert({
          'id': expense.id,
          'outlet_id': expense.outletId,
          'category': expense.category,
          'description': expense.description,
          'amount': expense.amount,
          'occurred_at': expense.occurredAt.toUtc().toIso8601String(),
          'created_at': expense.createdAt.toUtc().toIso8601String(),
        });
        await _db.financeDao.markExpenseSynced(expense.id);
      } catch (e) {
        debugPrint('[SyncService] push expense ${expense.id} failed: $e');
      }
    }
  }

  Future<bool> _isConnected() async {
    final results = await Connectivity().checkConnectivity();
    return _hasConnection(results);
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<Set<String>> _cloudEntitledOutletIds() async {
    final outlets = await _db.select(_db.outlets).get();
    if (outlets.isEmpty || _supabase.auth.currentUser?.email == null) {
      return const {};
    }

    final entitledOutletIds = <String>{};
    for (final outlet in outlets) {
      try {
        final response = await _supabase.functions.invoke(
          'get-plan-status',
          body: {'outlet_id': outlet.id},
        );
        final data = _asMap(response.data);
        if (data['error'] is String) continue;

        final isPro = data['is_pro'] == true;
        final isCloud = data['is_cloud'] == true;
        final expiresAt = _date(data['expires_at']);

        await (_db.update(_db.outlets)
              ..where((row) => row.id.equals(outlet.id)))
            .write(OutletsCompanion(
          licenseKey: Value(isPro ? 'PRO' : 'FREE'),
          licenseExpiry: const Value(null),
          cloudExpiry: Value(isCloud ? expiresAt : null),
        ));

        if (isCloud) entitledOutletIds.add(outlet.id);
      } catch (e) {
        debugPrint(
          '[SyncService] cloud entitlement check failed for ${outlet.id}: $e',
        );
      }
    }

    return entitledOutletIds;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _decodePayload(String value) {
    try {
      return _asMap(jsonDecode(value));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}

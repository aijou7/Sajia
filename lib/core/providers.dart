import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/app_database.dart';
import '../data/sync/sync_service.dart';
import '../domain/entities/entities.dart';
import 'onboarding_service.dart';

// Infrastructure
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final supabase = ref.watch(supabaseProvider);
  final service = SyncService(
    db,
    supabase,
    operationalOutletScope: () {
      final user = ref.read(currentUserProvider);
      if (user == null) return const <String>{};
      if (user.isOwner) return null;
      return user.accessibleOutletIds.toSet();
    },
  );
  ref.listen<AppUser?>(currentUserProvider, (_, next) {
    if (next != null) unawaited(service.syncAll());
  });
  ref.onDispose(service.dispose);
  return service;
});

// Onboarding
final isSetupDoneProvider = FutureProvider<bool>((ref) async {
  return OnboardingService().isSetupDone();
});

// Router refresh
final routerRefreshProvider = Provider<_RouterRefresh>((ref) {
  final notifier = _RouterRefresh();
  ref.listen(isSetupDoneProvider, (_, __) => notifier.notify());
  ref.listen(currentUserProvider, (_, __) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

// Auth / active session
abstract class WritableNotifier<T> extends Notifier<T> {
  @override
  T get state => super.state;

  @override
  set state(T value) => super.state = value;
}

class CurrentUserNotifier extends WritableNotifier<AppUser?> {
  @override
  AppUser? build() => null;
}

class CurrentOutletIdNotifier extends WritableNotifier<String> {
  @override
  String build() => 'default-outlet';
}

class ActiveShiftNotifier extends WritableNotifier<SessionData?> {
  @override
  SessionData? build() => null;
}

final currentUserProvider = NotifierProvider<CurrentUserNotifier, AppUser?>(
  CurrentUserNotifier.new,
);
final currentOutletIdProvider =
    NotifierProvider<CurrentOutletIdNotifier, String>(
  CurrentOutletIdNotifier.new,
);
final activeShiftProvider = NotifierProvider<ActiveShiftNotifier, SessionData?>(
  ActiveShiftNotifier.new,
);

final currentOutletProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return (db.select(db.outlets)..where((o) => o.id.equals(outletId)))
      .getSingleOrNull();
});

// Products
final categoriesProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.productDao.watchCategories(outletId);
});

final availableProductsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.productDao.watchAvailableProducts(outletId);
});

final allProductsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.productDao.watchProducts(outletId);
});

final lowStockProvider = FutureProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.productDao.getLowStockProducts(outletId);
});

// Orders and tables
final activeOrdersProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.orderDao.watchActiveOrders(outletId);
});

final tablesProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  return db.orderDao.watchTables(outletId);
});

final orderItemsProvider =
    StreamProvider.autoDispose.family<List<OrderItem>, String>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return db.orderDao.watchOrderItems(orderId);
});

/// Sinyal perubahan data bisnis yang dipakai laporan dan dashboard.
///
/// Query agregasi kedua halaman tersebut tetap dijalankan sebagai Future agar
/// perhitungannya sederhana, tetapi sinyal ini membuat Future dimuat ulang saat
/// transaksi, item transaksi, pengeluaran, atau outlet berubah (termasuk saat
/// hasil sinkronisasi baru masuk).
final businessDataRevisionProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT 1 AS revision',
        readsFrom: {db.orders, db.orderItems, db.expenses, db.outlets},
      )
      .watch()
      .map((_) => DateTime.now().microsecondsSinceEpoch);
});

// Cart
class CartNotifier extends WritableNotifier<Cart> {
  @override
  Cart build() => const Cart();

  void addItem(CartItem item) {
    final existingIndex = state.items.indexWhere(
      (i) =>
          i.productId == item.productId &&
          i.variantSummary == item.variantSummary,
    );
    if (existingIndex >= 0) {
      final updated = List<CartItem>.from(state.items);
      final existing = updated[existingIndex];
      final nextQty = existing.quantity + item.quantity;
      if (existing.trackStock &&
          existing.availableStock != null &&
          nextQty > existing.availableStock!) {
        return;
      }
      updated[existingIndex] = existing.copyWith(quantity: nextQty);
      state = state.copyWith(items: updated);
    } else {
      if (item.trackStock &&
          item.availableStock != null &&
          item.quantity > item.availableStock!) {
        return;
      }
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  void incrementQty(int index) {
    if (index < 0 || index >= state.items.length) return;
    final current = state.items[index];
    final nextQty = current.quantity + 1;
    if (current.trackStock &&
        current.availableStock != null &&
        nextQty > current.availableStock!) {
      return;
    }
    updateQty(index, nextQty);
  }

  void decrementQty(int index) {
    if (index < 0 || index >= state.items.length) return;
    final current = state.items[index];
    updateQty(index, current.quantity - 1);
  }

  void updateQty(int index, double qty) {
    if (index < 0 || index >= state.items.length) return;
    if (qty <= 0) {
      removeItem(index);
      return;
    }
    final updated = List<CartItem>.from(state.items);
    updated[index] = updated[index].copyWith(quantity: qty);
    state = state.copyWith(items: updated);
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.items.length) return;
    final updated = List<CartItem>.from(state.items)..removeAt(index);
    state = state.copyWith(items: updated);
  }

  void setTable(String? tableId, String? tableLabel) =>
      state = state.copyWith(tableId: tableId, tableLabel: tableLabel);

  void setOrderType(String type) => state = state.copyWith(orderType: type);

  void setDiscount({double percent = 0, double amount = 0}) {
    final safePercent =
        percent.isFinite ? percent.clamp(0, 100).toDouble() : 0.0;
    final safeAmount =
        amount.isFinite ? amount.clamp(0, state.subtotal).toDouble() : 0.0;
    state = state.copyWith(
      discountPercent: safePercent,
      discountAmount: safeAmount,
    );
  }

  void setNotes(String? notes) => state = state.copyWith(notes: notes);

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(
  CartNotifier.new,
);

class HeldOrdersNotifier extends WritableNotifier<List<Cart>> {
  @override
  List<Cart> build() => [];
}

final heldOrdersProvider = NotifierProvider<HeldOrdersNotifier, List<Cart>>(
  HeldOrdersNotifier.new,
);

// Reports
class SelectedReportDateNotifier extends WritableNotifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
}

final selectedReportDateProvider =
    NotifierProvider<SelectedReportDateNotifier, DateTime>(
  SelectedReportDateNotifier.new,
);

final dailySalesSummaryProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  final date = ref.watch(selectedReportDateProvider);
  return db.orderDao.getSalesSummary(
    outletId,
    DateTime(date.year, date.month, date.day),
    DateTime(date.year, date.month, date.day, 23, 59, 59),
  );
});

final topProductsProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(databaseProvider);
  final outletId = ref.watch(currentOutletIdProvider);
  final date = ref.watch(selectedReportDateProvider);
  return db.orderDao.getTopProducts(
    outletId,
    DateTime(date.year, date.month, date.day),
    DateTime(date.year, date.month, date.day, 23, 59, 59),
  );
});

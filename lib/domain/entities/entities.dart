import 'package:equatable/equatable.dart';

class CartItem extends Equatable {
  final String productId;
  final String productName;
  final double unitPrice;
  final double unitCogs;
  final double quantity;
  final double discount;
  final String? notes;
  final String? variantSummary;
  final bool trackStock;
  final double? availableStock;
  final String? categoryId;
  final String? categoryName;

  const CartItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    this.unitCogs = 0,
    this.quantity = 1,
    this.discount = 0,
    this.notes,
    this.variantSummary,
    this.trackStock = false,
    this.availableStock,
    this.categoryId,
    this.categoryName,
  });

  double get subtotal => (unitPrice - discount) * quantity;

  CartItem copyWith({double? quantity, double? discount, String? notes}) =>
      CartItem(
        productId: productId,
        productName: productName,
        unitPrice: unitPrice,
        unitCogs: unitCogs,
        quantity: quantity ?? this.quantity,
        discount: discount ?? this.discount,
        notes: notes ?? this.notes,
        variantSummary: variantSummary,
        trackStock: trackStock,
        availableStock: availableStock,
        categoryId: categoryId,
        categoryName: categoryName,
      );

  @override
  List<Object?> get props => [
        productId,
        productName,
        unitPrice,
        unitCogs,
        quantity,
        discount,
        notes,
        variantSummary,
        trackStock,
        availableStock,
        categoryId,
        categoryName,
      ];
}

class Cart extends Equatable {
  final List<CartItem> items;
  final String? tableId;
  final String? tableLabel;
  final String orderType;
  final double discountPercent;
  final double discountAmount;
  final String? customerName;
  final String? notes;

  const Cart({
    this.items = const [],
    this.tableId,
    this.tableLabel,
    this.orderType = 'dine_in',
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.customerName,
    this.notes,
  });

  double get subtotal => items.fold(0, (sum, i) => sum + i.subtotal);
  double get discountValue =>
      discountAmount > 0 ? discountAmount : subtotal * discountPercent / 100;
  double get subtotalAfterDiscount => subtotal - discountValue;
  double taxAmount(double taxPercent) =>
      subtotalAfterDiscount * taxPercent / 100;
  double serviceChargeAmount(double servicePercent) =>
      subtotalAfterDiscount * servicePercent / 100;
  double total(double taxPercent, double servicePercent) =>
      subtotalAfterDiscount +
      taxAmount(taxPercent) +
      serviceChargeAmount(servicePercent);
  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity.toInt());

  Cart copyWith({
    List<CartItem>? items,
    String? tableId,
    String? tableLabel,
    String? orderType,
    double? discountPercent,
    double? discountAmount,
    String? customerName,
    String? notes,
  }) =>
      Cart(
        items: items ?? this.items,
        tableId: tableId ?? this.tableId,
        tableLabel: tableLabel ?? this.tableLabel,
        orderType: orderType ?? this.orderType,
        discountPercent: discountPercent ?? this.discountPercent,
        discountAmount: discountAmount ?? this.discountAmount,
        customerName: customerName ?? this.customerName,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [
        items,
        tableId,
        tableLabel,
        orderType,
        discountPercent,
        discountAmount,
        customerName,
        notes,
      ];
}

class AppUser extends Equatable {
  final String id;
  final String name;
  final String role;
  final String outletId;
  final List<String> assignedOutletIds;

  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.outletId,
    this.assignedOutletIds = const [],
  });

  bool get isOwner => role == 'owner';
  bool get isManager => role == 'manager';
  bool get isCashier => role == 'cashier';
  bool get canManageOperations => isOwner || isManager;
  bool get canViewSalesHistory => isOwner || isManager || isCashier;
  bool get canVoidTransactions => isOwner || isManager;
  bool get canViewFinancialReports => isOwner || isManager;
  bool get canViewAllBranches => isOwner;
  bool get canManageUsers => isOwner;
  List<String> get accessibleOutletIds => isOwner
      ? const []
      : (assignedOutletIds.isEmpty ? [outletId] : assignedOutletIds);

  bool canAccessOutlet(String outletId) =>
      isOwner || accessibleOutletIds.contains(outletId);

  String get roleLabel => switch (role) {
        'owner' => 'Owner',
        'manager' => 'Manager',
        _ => 'Kasir',
      };

  @override
  List<Object?> get props => [id, name, role, outletId, assignedOutletIds];
}

// FIX: Renamed dari Session ke SessionData untuk avoid conflict dengan Supabase Session
class SessionData extends Equatable {
  final String id;
  final String cashierId;
  final String cashierName;
  final double openingCash;
  final DateTime openedAt;

  const SessionData({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.openingCash,
    required this.openedAt,
  });

  @override
  List<Object?> get props => [id];
}

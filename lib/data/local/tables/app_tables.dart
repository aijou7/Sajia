import 'package:drift/drift.dart';

// ─────────────────────────────────────────────
// USERS
// ─────────────────────────────────────────────
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get pin => text()();
  TextColumn get role => text()(); // 'owner' | 'manager' | 'cashier'
  TextColumn get outletId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// OUTLETS
// ─────────────────────────────────────────────
class UserOutletAccesses extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get outletId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Outlets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get taxPercent => text().withDefault(const Constant('0'))();
  TextColumn get serviceChargePercent =>
      text().withDefault(const Constant('0'))();
  TextColumn get receiptHeader => text().nullable()();
  TextColumn get receiptFooter => text().nullable()();
  TextColumn get licenseKey => text()();
  DateTimeColumn get licenseExpiry => dateTime().nullable()();
  DateTimeColumn get cloudExpiry => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// CATEGORIES
// ─────────────────────────────────────────────
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get colorHex => text().withDefault(const Constant('#888888'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// PRODUCTS
// ─────────────────────────────────────────────
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get price => text()();
  TextColumn get cogs => text().withDefault(const Constant('0'))();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  BoolColumn get trackStock => boolean().withDefault(const Constant(false))();
  TextColumn get stock => text().withDefault(const Constant('0'))();
  TextColumn get lowStockAlert => text().withDefault(const Constant('5'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// PRODUCT VARIANTS
// ─────────────────────────────────────────────
class ProductVariants extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get name => text()();
  TextColumn get options => text()(); // JSON
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// RESTAURANT TABLES
// ─────────────────────────────────────────────
class RestaurantTables extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get tableLabel => text()(); // RENAMED dari tableName → tableLabel
  TextColumn get area => text().nullable()();
  IntColumn get capacity => integer().withDefault(const Constant(4))();
  TextColumn get status => text().withDefault(const Constant('available'))();
  TextColumn get currentOrderId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// ORDERS
// ─────────────────────────────────────────────
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get orderNumber => text()();
  TextColumn get type => text()(); // 'dine_in' | 'takeaway' | 'delivery'
  TextColumn get status => text()();
  TextColumn get tableId => text().nullable()();
  TextColumn get tableLabel =>
      text().nullable()(); // RENAMED dari tableName → tableLabel
  TextColumn get cashierId => text()();
  TextColumn get cashierName => text()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerCount => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get subtotal => text().withDefault(const Constant('0'))();
  TextColumn get discountAmount => text().withDefault(const Constant('0'))();
  TextColumn get discountPercent => text().withDefault(const Constant('0'))();
  TextColumn get taxAmount => text().withDefault(const Constant('0'))();
  TextColumn get serviceCharge => text().withDefault(const Constant('0'))();
  TextColumn get total => text().withDefault(const Constant('0'))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get paidAmount => text().nullable()();
  TextColumn get changeAmount => text().nullable()();
  TextColumn get paymentRef => text().nullable()();
  DateTimeColumn get paidAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
  TextColumn get voidedBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// ORDER ITEMS
// ─────────────────────────────────────────────
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  TextColumn get variantSummary => text().nullable()();
  TextColumn get unitPrice => text()();
  TextColumn get quantity => text()();
  TextColumn get discount => text().withDefault(const Constant('0'))();
  TextColumn get subtotal => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// SESSIONS
// ─────────────────────────────────────────────
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get cashierId => text()();
  TextColumn get cashierName => text()();
  TextColumn get openingCash => text().withDefault(const Constant('0'))();
  TextColumn get closingCash => text().nullable()();
  TextColumn get totalCashSales => text().withDefault(const Constant('0'))();
  TextColumn get totalQrisSales => text().withDefault(const Constant('0'))();
  IntColumn get totalOrders =>
      integer().withDefault(const Constant(0))(); // FIX: IntColumn
  IntColumn get totalVoids =>
      integer().withDefault(const Constant(0))(); // FIX: IntColumn
  TextColumn get notes => text().nullable()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────
// SYNC QUEUE
// ─────────────────────────────────────────────
/// Beban operasional untuk laporan laba-rugi per outlet.
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get outletId => text()();
  TextColumn get category => text()();
  TextColumn get description => text().nullable()();
  TextColumn get amount => text()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncTableName =>
      text()(); // RENAMED dari tableName → syncTableName
  TextColumn get recordId => text()();
  TextColumn get operation => text()(); // 'insert' | 'update' | 'delete'
  TextColumn get payload => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastRetryAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
}

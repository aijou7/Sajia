import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/numeric_input_formatter.dart';
import '../../core/theme.dart';

class OwnerOutletOption {
  final String id;
  final String name;
  final bool isCloud;

  const OwnerOutletOption({
    required this.id,
    required this.name,
    required this.isCloud,
  });
}

class OwnerOperationsPage extends StatefulWidget {
  final List<OwnerOutletOption> outlets;

  const OwnerOperationsPage({super.key, required this.outlets});

  @override
  State<OwnerOperationsPage> createState() => _OwnerOperationsPageState();
}

class _OwnerOperationsPageState extends State<OwnerOperationsPage> {
  late Future<_OperationsData> _data;
  String? _outletId;
  _OperationsTab _selectedTab = _OperationsTab.menu;

  OwnerOutletOption? get _selectedOutlet {
    for (final outlet in widget.outlets) {
      if (outlet.id == _outletId) return outlet;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _outletId = widget.outlets.isEmpty ? null : widget.outlets.first.id;
    _data = _loadData();
  }

  @override
  void didUpdateWidget(covariant OwnerOperationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.outlets.any((outlet) => outlet.id == _outletId)) return;
    _outletId = widget.outlets.isEmpty ? null : widget.outlets.first.id;
    _data = _loadData();
  }

  Future<_OperationsData> _loadData() async {
    final outlet = _selectedOutlet;
    if (outlet == null) return const _OperationsData.empty();

    final client = Supabase.instance.client;
    final responses = await Future.wait<dynamic>([
      client
          .from('categories')
          .select()
          .eq('outlet_id', outlet.id)
          .order('sort_order'),
      client
          .from('products')
          .select()
          .eq('outlet_id', outlet.id)
          .order('sort_order'),
      client
          .from('restaurant_tables')
          .select()
          .eq('outlet_id', outlet.id)
          .order('table_label'),
      if (outlet.isCloud)
        client
            .from('expenses')
            .select()
            .eq('outlet_id', outlet.id)
            .order('occurred_at', ascending: false)
            .limit(150)
      else
        Future.value(const <dynamic>[]),
    ]);

    // The promo migration is additive. Keep the existing operational
    // dashboard usable during a staged rollout if an older Cloud project does
    // not have the two new tables yet.
    var promotionRows = const <Map<String, dynamic>>[];
    var promotionItems = const <Map<String, dynamic>>[];
    try {
      promotionRows = ((await client
                  .from('scheduled_promotions')
                  .select()
                  .eq('outlet_id', outlet.id)
                  .order('priority', ascending: false)
                  .order('updated_at', ascending: false)) as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(growable: false);
      final promotionIds = promotionRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (promotionIds.isNotEmpty) {
        promotionItems = ((await client
                    .from('scheduled_promotion_items')
                    .select()
                    .inFilter('promotion_id', promotionIds)) as List)
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList(growable: false);
      }
    } catch (_) {
      // The editor will simply remain empty until the migration is applied.
    }
    final promotionItemsByPromotion = <String, List<_OwnerPromotionItem>>{};
    for (final item in promotionItems) {
      final promotionId = item['promotion_id']?.toString();
      if (promotionId == null || promotionId.isEmpty) continue;
      promotionItemsByPromotion
          .putIfAbsent(promotionId, () => [])
          .add(_OwnerPromotionItem.fromJson(item));
    }

    return _OperationsData(
      categories: (responses[0] as List)
          .map((row) => _OwnerCategory.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      products: (responses[1] as List)
          .map((row) => _OwnerProduct.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      tables: (responses[2] as List)
          .map((row) => _OwnerTable.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      expenses: (responses[3] as List)
          .map((row) => _OwnerExpense.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      promotions: promotionRows
          .map(
            (row) => _OwnerScheduledPromotion.fromJson(
              row,
              promotionItemsByPromotion[row['id']?.toString()] ?? const [],
            ),
          )
          .toList(),
    );
  }

  void _reload() => setState(() => _data = _loadData());

  Future<void> _saveCategory({
    required _OwnerCategory? category,
    required String name,
    required String colorHex,
    required bool isActive,
  }) async {
    final outletId = _outletId;
    if (outletId == null) return;
    final payload = {
      'name': name.trim(),
      'color_hex': colorHex.toUpperCase(),
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final table = Supabase.instance.client.from('categories');
    if (category == null) {
      await table.insert({
        ...payload,
        'id': const Uuid().v4(),
        'outlet_id': outletId,
        'sort_order': 0,
      });
    } else {
      await table.update(payload).eq('id', category.id).eq('outlet_id', outletId);
    }
    _reload();
  }

  Future<void> _saveProduct({
    required _OwnerProduct? product,
    required String? categoryId,
    required String name,
    required String? description,
    required String price,
    required String cogs,
    required bool isAvailable,
    required bool trackStock,
    required String stock,
    required String lowStockAlert,
  }) async {
    final outletId = _outletId;
    if (outletId == null) return;
    final payload = {
      'category_id': categoryId,
      'name': name.trim(),
      'description': _emptyToNull(description),
      'price': price,
      'cogs': cogs,
      'is_available': isAvailable,
      'low_stock_alert': lowStockAlert,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final table = Supabase.instance.client.from('products');
    if (product == null) {
      await table.insert({
        ...payload,
        'id': const Uuid().v4(),
        'outlet_id': outletId,
        // A product created in the portal cannot have a prior sale/reversal
        // on another device, so its opening stock can be written safely.
        'track_stock': trackStock,
        'stock': stock,
        'sort_order': 0,
      });
    } else {
      // Stock and the tracking mode are protected separately. Updating either
      // as part of a general product edit can lose a sale/reversal that an
      // offline cashier device is currently syncing.
      await table.update(payload).eq('id', product.id).eq('outlet_id', outletId);
    }
    _reload();
  }

  Future<void> _adjustProductStock({
    required _OwnerProduct product,
    required String newStock,
  }) async {
    final expectedStock = _parseNumber(product.stock);
    final requestedStock = _parseNumber(newStock);
    if (expectedStock == null || requestedStock == null) {
      throw const FormatException('Stok tidak valid.');
    }
    final response = await Supabase.instance.client.rpc(
      'set_owner_product_stock_if_current',
      params: {
        'p_product_id': product.id,
        'p_expected_stock': expectedStock,
        'p_new_stock': requestedStock,
      },
    );
    final result = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    _reload();
    if (result['applied'] != true) {
      throw _StockConflictException(result['current_stock']?.toString());
    }
  }

  Future<void> _saveTable({
    required _OwnerTable? table,
    required String label,
    required String? area,
    required int capacity,
  }) async {
    final outletId = _outletId;
    if (outletId == null) return;
    final payload = {
      'table_label': label.trim(),
      'area': _emptyToNull(area),
      'capacity': capacity,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final remote = Supabase.instance.client.from('restaurant_tables');
    if (table == null) {
      await remote.insert({
        ...payload,
        'id': const Uuid().v4(),
        'outlet_id': outletId,
        'status': 'available',
        'current_order_id': null,
      });
    } else {
      await remote.update(payload).eq('id', table.id).eq('outlet_id', outletId);
    }
    _reload();
  }

  Future<void> _saveExpense({
    required _OwnerExpense? expense,
    required String category,
    required String? description,
    required String amount,
    required DateTime occurredAt,
  }) async {
    final outlet = _selectedOutlet;
    if (outlet == null || !outlet.isCloud) return;
    final payload = {
      'category': category.trim(),
      'description': _emptyToNull(description),
      'amount': amount,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
    };
    final remote = Supabase.instance.client.from('expenses');
    if (expense == null) {
      await remote.insert({
        ...payload,
        'id': const Uuid().v4(),
        'outlet_id': outlet.id,
      });
    } else {
      await remote.update(payload).eq('id', expense.id).eq('outlet_id', outlet.id);
    }
    _reload();
  }

  Future<void> _savePromotion({
    required _OwnerScheduledPromotion? promotion,
    required String name,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required Set<int> activeWeekdays,
    required String scheduleMode,
    required DateTime? startDate,
    required DateTime? endDate,
    required bool isActive,
    required List<_OwnerPromotionItemDraft> items,
  }) async {
    final outletId = _outletId;
    if (outletId == null) return;
    final client = Supabase.instance.client;
    final id = promotion?.id ?? const Uuid().v4();
    final itemPayload = items
        .map((item) => {
              'product_id': item.productId,
              'promo_price': item.promoPrice,
            })
        .toList(growable: false);
    final sharedParams = {
      'p_id': id,
      'p_outlet_id': outletId,
      'p_name': name.trim(),
      'p_start_time': _timeOfDaySql(startTime),
      'p_end_time': _timeOfDaySql(endTime),
      'p_active_days': activeWeekdays.toList()..sort(),
      'p_is_active': isActive,
      'p_items': itemPayload,
    };

    try {
      await client.rpc(
        'upsert_scheduled_promotion',
        params: {
          ...sharedParams,
          'p_schedule_mode': scheduleMode,
          'p_start_date': _dateOnlySql(startDate),
          'p_end_date': _dateOnlySql(endDate),
        },
      );
    } on PostgrestException catch (error) {
      // Older projects may still expose the original 8-argument RPC. Keep
      // weekly promos usable while the additive date-range migration rolls
      // out; date-range promos still need the new overload.
      if (scheduleMode != 'WEEKLY' || !_isMissingPromotionScheduleRpc(error)) {
        rethrow;
      }
      await client.rpc(
        'upsert_scheduled_promotion',
        params: sharedParams,
      );
    }
    _reload();
  }

  Future<void> _deletePromotion(_OwnerScheduledPromotion promotion) async {
    await Supabase.instance.client.rpc(
      'delete_scheduled_promotion',
      params: {'p_id': promotion.id},
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => _OperationsPageShell(
        child: widget.outlets.isEmpty
            ? const _OwnerOperationsEmpty(
                icon: Icons.storefront_outlined,
                title: 'Belum ada cabang',
                message: 'Buat cabang dari aplikasi Sajia terlebih dahulu.',
              )
            : FutureBuilder<_OperationsData>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _OwnerOperationsEmpty(
                      icon: Icons.cloud_off_outlined,
                      title: 'Data operasional belum dapat dimuat',
                      message:
                          'Periksa koneksi dan akses Cloud, lalu coba muat ulang.',
                      action: FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Coba lagi'),
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  final outlet = _selectedOutlet!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Data operasional',
                                    style: TextStyle(
                                        fontSize: 28, fontWeight: FontWeight.w900)),
                                SizedBox(height: 6),
                                Text(
                                  'Kelola menu, meja, stok awal, dan pengeluaran dari browser.',
                                  style: TextStyle(color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Muat ulang data',
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_outletId),
                        initialValue: _outletId,
                        decoration: const InputDecoration(
                          labelText: 'Cabang',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        items: widget.outlets
                            .map((item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.name),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null || value == _outletId) return;
                          setState(() {
                            _outletId = value;
                            _data = _loadData();
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tab in _OperationsTab.values)
                            ChoiceChip(
                              label: Text(tab.label),
                              avatar: Icon(tab.icon, size: 17),
                              selected: _selectedTab == tab,
                              onSelected: (_) =>
                                  setState(() => _selectedTab = tab),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      switch (_selectedTab) {
                        _OperationsTab.menu => _MenuDataPanel(
                            data: data,
                            outletId: outlet.id,
                            onAddCategory: () => _openCategoryEditor(context),
                            onEditCategory: (category) =>
                                _openCategoryEditor(context, category: category),
                            onAddProduct: () => _openProductEditor(context, data),
                            onEditProduct: (product) =>
                                _openProductEditor(context, data, product: product),
                            onAdjustProductStock: (product) =>
                                _openStockAdjustment(context, product),
                          ),
                        _OperationsTab.tables => _TableDataPanel(
                            tables: data.tables,
                            onAdd: () => _openTableEditor(context),
                            onEdit: (table) =>
                                _openTableEditor(context, table: table),
                          ),
                        _OperationsTab.expenses => outlet.isCloud
                            ? _ExpenseDataPanel(
                                expenses: data.expenses,
                                onAdd: () => _openExpenseEditor(context),
                                onEdit: (expense) =>
                                    _openExpenseEditor(context, expense: expense),
                              )
                            : const _OwnerOperationsEmpty(
                                icon: Icons.cloud_outlined,
                                title: 'Pengeluaran membutuhkan Cloud',
                                message:
                                    'Aktifkan paket Cloud untuk cabang ini agar pengeluaran dan laporan keuangan tersinkron.',
                              ),
                        _OperationsTab.promotions => _PromotionDataPanel(
                            promotions: data.promotions,
                            products: data.products,
                            onAdd: () => _openPromotionEditor(context, data),
                            onEdit: (promotion) =>
                                _openPromotionEditor(context, data, promotion: promotion),
                            onDelete: (promotion) =>
                                _confirmDeletePromotion(context, promotion),
                          ),
                      },
                    ],
                  );
                },
              ),
      );

  Future<void> _openCategoryEditor(
    BuildContext context, {
    _OwnerCategory? category,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoryEditor(
        category: category,
        onSave: _saveCategory,
      ),
    );
  }

  Future<void> _openProductEditor(
    BuildContext context,
    _OperationsData data, {
    _OwnerProduct? product,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProductEditor(
        product: product,
        categories: data.categories,
        onSave: _saveProduct,
      ),
    );
  }

  Future<void> _openStockAdjustment(
    BuildContext context,
    _OwnerProduct product,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StockAdjustmentDialog(
        product: product,
        onSave: (stock) => _adjustProductStock(
          product: product,
          newStock: stock,
        ),
      ),
    );
  }

  Future<void> _openTableEditor(
    BuildContext context, {
    _OwnerTable? table,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TableEditor(table: table, onSave: _saveTable),
    );
  }

  Future<void> _openExpenseEditor(
    BuildContext context, {
    _OwnerExpense? expense,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ExpenseEditor(expense: expense, onSave: _saveExpense),
    );
  }

  Future<void> _openPromotionEditor(
    BuildContext context,
    _OperationsData data, {
    _OwnerScheduledPromotion? promotion,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PromotionEditor(
        promotion: promotion,
        products: data.products,
        onSave: _savePromotion,
      ),
    );
  }

  Future<void> _confirmDeletePromotion(
    BuildContext context,
    _OwnerScheduledPromotion promotion,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus promo?'),
        content: Text(
          '“${promotion.name}” akan dihapus dan tidak lagi dipakai oleh kasir setelah sinkronisasi berikutnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _deletePromotion(promotion);
    } on PostgrestException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promo belum dapat dihapus. Coba lagi.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promo belum dapat dihapus. Periksa koneksi.')),
      );
    }
  }
}

enum _OperationsTab { menu, tables, expenses, promotions }

extension on _OperationsTab {
  String get label => switch (this) {
        _OperationsTab.menu => 'Menu',
        _OperationsTab.tables => 'Meja',
        _OperationsTab.expenses => 'Pengeluaran',
        _OperationsTab.promotions => 'Promo',
      };

  IconData get icon => switch (this) {
        _OperationsTab.menu => Icons.restaurant_menu_rounded,
        _OperationsTab.tables => Icons.table_restaurant_outlined,
        _OperationsTab.expenses => Icons.receipt_long_outlined,
        _OperationsTab.promotions => Icons.schedule_rounded,
      };
}

class _CategoryColorOption {
  final String name;
  final String hex;

  const _CategoryColorOption(this.name, this.hex);
}

const _categoryColorPalette = <_CategoryColorOption>[
  _CategoryColorOption('Teal', '#356B66'),
  _CategoryColorOption('Sage', '#6F9E98'),
  _CategoryColorOption('Ungu lembut', '#746FA8'),
  _CategoryColorOption('Biru', '#557FA3'),
  _CategoryColorOption('Hijau', '#2F7D64'),
  _CategoryColorOption('Oranye', '#C57843'),
  _CategoryColorOption('Merah', '#C55252'),
  _CategoryColorOption('Mauve', '#8A6E82'),
  _CategoryColorOption('Biru abu', '#68809B'),
  _CategoryColorOption('Abu hijau', '#73807C'),
  _CategoryColorOption('Cokelat', '#9B776D'),
  _CategoryColorOption('Hijau tua', '#596C68'),
  _CategoryColorOption('Biru terang', '#7D8FA8'),
];

class _OperationsData {
  final List<_OwnerCategory> categories;
  final List<_OwnerProduct> products;
  final List<_OwnerTable> tables;
  final List<_OwnerExpense> expenses;
  final List<_OwnerScheduledPromotion> promotions;

  const _OperationsData({
    required this.categories,
    required this.products,
    required this.tables,
    required this.expenses,
    required this.promotions,
  });

  const _OperationsData.empty()
      : categories = const [],
        products = const [],
        tables = const [],
        expenses = const [],
        promotions = const [];
}

class _OwnerCategory {
  final String id;
  final String name;
  final String colorHex;
  final bool isActive;

  const _OwnerCategory({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.isActive,
  });

  factory _OwnerCategory.fromJson(Map<String, dynamic> json) => _OwnerCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Kategori',
        colorHex: json['color_hex']?.toString() ?? '#888888',
        isActive: json['is_active'] != false,
      );
}

class _OwnerProduct {
  final String id;
  final String? categoryId;
  final String name;
  final String? description;
  final String price;
  final String cogs;
  final bool isAvailable;
  final bool trackStock;
  final String stock;
  final String lowStockAlert;

  const _OwnerProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.cogs,
    required this.isAvailable,
    required this.trackStock,
    required this.stock,
    required this.lowStockAlert,
  });

  factory _OwnerProduct.fromJson(Map<String, dynamic> json) => _OwnerProduct(
        id: json['id']?.toString() ?? '',
        categoryId: json['category_id']?.toString(),
        name: json['name']?.toString() ?? 'Menu',
        description: json['description']?.toString(),
        price: json['price']?.toString() ?? '0',
        cogs: json['cogs']?.toString() ?? '0',
        isAvailable: json['is_available'] != false,
        trackStock: json['track_stock'] == true,
        stock: json['stock']?.toString() ?? '0',
        lowStockAlert: json['low_stock_alert']?.toString() ?? '5',
      );
}

class _OwnerTable {
  final String id;
  final String label;
  final String? area;
  final int capacity;
  final String status;

  const _OwnerTable({
    required this.id,
    required this.label,
    required this.area,
    required this.capacity,
    required this.status,
  });

  factory _OwnerTable.fromJson(Map<String, dynamic> json) => _OwnerTable(
        id: json['id']?.toString() ?? '',
        label: json['table_label']?.toString() ?? 'Meja',
        area: json['area']?.toString(),
        capacity: _asInt(json['capacity'], fallback: 4),
        status: json['status']?.toString() ?? 'available',
      );
}

class _OwnerExpense {
  final String id;
  final String category;
  final String? description;
  final String amount;
  final DateTime occurredAt;

  const _OwnerExpense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.occurredAt,
  });

  factory _OwnerExpense.fromJson(Map<String, dynamic> json) => _OwnerExpense(
        id: json['id']?.toString() ?? '',
        category: json['category']?.toString() ?? 'Operasional',
        description: json['description']?.toString(),
        amount: json['amount']?.toString() ?? '0',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class _OwnerScheduledPromotion {
  const _OwnerScheduledPromotion({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.activeWeekdays,
    required this.scheduleMode,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.items,
  });

  final String id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Set<int> activeWeekdays;
  final String scheduleMode;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final List<_OwnerPromotionItem> items;

  factory _OwnerScheduledPromotion.fromJson(
    Map<String, dynamic> json,
    List<_OwnerPromotionItem> items,
  ) =>
      _OwnerScheduledPromotion(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Promo',
        startTime: _timeOfDayFromSql(json['start_time']?.toString()),
        endTime: _timeOfDayFromSql(json['end_time']?.toString()),
        activeWeekdays: _weekdaysFromJson(json['active_days']),
        scheduleMode: json['schedule_mode']?.toString().toUpperCase() == 'DATE_RANGE'
            ? 'DATE_RANGE'
            : 'WEEKLY',
        startDate: _dateOnlyFromSql(json['start_date']?.toString()),
        endDate: _dateOnlyFromSql(json['end_date']?.toString()),
        isActive: json['is_active'] != false,
        items: List.unmodifiable(items),
      );
}

class _OwnerPromotionItem {
  const _OwnerPromotionItem({
    required this.id,
    required this.productId,
    required this.promoPrice,
  });

  final String id;
  final String productId;
  final double promoPrice;

  factory _OwnerPromotionItem.fromJson(Map<String, dynamic> json) =>
      _OwnerPromotionItem(
        id: json['id']?.toString() ?? '',
        productId: json['product_id']?.toString() ?? '',
        promoPrice: _parseNumber(json['promo_price']?.toString() ?? '') ?? 0,
      );
}

class _OwnerPromotionItemDraft {
  const _OwnerPromotionItemDraft({
    required this.productId,
    required this.promoPrice,
  });

  final String productId;
  final double promoPrice;
}

class _MenuDataPanel extends StatelessWidget {
  final _OperationsData data;
  final String outletId;
  final VoidCallback onAddCategory;
  final ValueChanged<_OwnerCategory> onEditCategory;
  final VoidCallback onAddProduct;
  final ValueChanged<_OwnerProduct> onEditProduct;
  final ValueChanged<_OwnerProduct> onAdjustProductStock;

  const _MenuDataPanel({
    required this.data,
    required this.outletId,
    required this.onAddCategory,
    required this.onEditCategory,
    required this.onAddProduct,
    required this.onEditProduct,
    required this.onAdjustProductStock,
  });

  @override
  Widget build(BuildContext context) {
    final categoryNames = {for (final category in data.categories) category.id: category.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          title: 'Kategori',
          subtitle: 'Kelompokkan menu supaya lebih mudah dicari di kasir.',
          actionLabel: 'Tambah kategori',
          actionIcon: Icons.add_rounded,
          onAction: onAddCategory,
        ),
        const SizedBox(height: 12),
        if (data.categories.isEmpty)
          const _OwnerOperationsEmpty(
            icon: Icons.category_outlined,
            title: 'Belum ada kategori',
            message: 'Tambah kategori pertama untuk mulai mengatur menu.',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < data.categories.length; index++) ...[
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _colorFromHex(data.categories[index].colorHex)
                          .withValues(alpha: .16),
                      child: Icon(Icons.category_outlined,
                          color: _colorFromHex(data.categories[index].colorHex)),
                    ),
                    title: Text(data.categories[index].name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(data.categories[index].isActive
                        ? 'Aktif'
                        : 'Disembunyikan dari kasir'),
                    trailing: IconButton(
                      tooltip: 'Ubah kategori',
                      onPressed: () => onEditCategory(data.categories[index]),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  if (index < data.categories.length - 1)
                    const Divider(height: 1, indent: 72),
                ],
              ],
            ),
          ),
        const SizedBox(height: 30),
        _PanelHeader(
          title: 'Menu',
          subtitle: 'Tambah atau ubah harga, HPP, ketersediaan, dan stok awal.',
          actionLabel: 'Tambah menu',
          actionIcon: Icons.add_rounded,
          onAction: onAddProduct,
        ),
        const SizedBox(height: 12),
        if (data.products.isEmpty)
          const _OwnerOperationsEmpty(
            icon: Icons.restaurant_menu_outlined,
            title: 'Belum ada menu',
            message: 'Tambah menu pertama agar bisa muncul di kasir.',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < data.products.length; index++) ...[
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    title: Text(data.products[index].name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      '${categoryNames[data.products[index].categoryId] ?? 'Tanpa kategori'} · '
                      '${_rupiah(data.products[index].price)}'
                      '${data.products[index].trackStock ? ' · Stok ${_numberLabel(data.products[index].stock)}' : ''}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusPill(
                          label: data.products[index].isAvailable
                              ? 'Aktif'
                              : 'Nonaktif',
                          active: data.products[index].isAvailable,
                        ),
                        IconButton(
                          tooltip: 'Ubah menu',
                          onPressed: () => onEditProduct(data.products[index]),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        if (data.products[index].trackStock)
                          IconButton(
                            tooltip: 'Sesuaikan stok',
                            onPressed: () =>
                                onAdjustProductStock(data.products[index]),
                            icon: const Icon(Icons.inventory_2_outlined),
                          ),
                      ],
                    ),
                  ),
                  if (index < data.products.length - 1)
                    const Divider(height: 1, indent: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TableDataPanel extends StatelessWidget {
  final List<_OwnerTable> tables;
  final VoidCallback onAdd;
  final ValueChanged<_OwnerTable> onEdit;

  const _TableDataPanel({
    required this.tables,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Meja',
            subtitle: 'Atur label, area, dan kapasitas meja untuk kasir dine-in.',
            actionLabel: 'Tambah meja',
            actionIcon: Icons.add_rounded,
            onAction: onAdd,
          ),
          const SizedBox(height: 12),
          if (tables.isEmpty)
            const _OwnerOperationsEmpty(
              icon: Icons.table_restaurant_outlined,
              title: 'Belum ada meja',
              message: 'Tambah meja untuk mulai menerima pesanan dine-in.',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < tables.length; index++) ...[
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.primaryLight,
                        child: Icon(Icons.table_restaurant_outlined,
                            color: AppTheme.primary),
                      ),
                      title: Text(tables[index].label,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '${tables[index].area ?? 'Area umum'} · ${tables[index].capacity} kursi · ${_tableStatusLabel(tables[index].status)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Ubah meja',
                        onPressed: () => onEdit(tables[index]),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                    if (index < tables.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
        ],
      );
}

class _ExpenseDataPanel extends StatelessWidget {
  final List<_OwnerExpense> expenses;
  final VoidCallback onAdd;
  final ValueChanged<_OwnerExpense> onEdit;

  const _ExpenseDataPanel({
    required this.expenses,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Pengeluaran',
            subtitle: 'Catat biaya operasional agar laba rugi tetap akurat.',
            actionLabel: 'Catat pengeluaran',
            actionIcon: Icons.add_rounded,
            onAction: onAdd,
          ),
          const SizedBox(height: 12),
          if (expenses.isEmpty)
            const _OwnerOperationsEmpty(
              icon: Icons.receipt_long_outlined,
              title: 'Belum ada pengeluaran',
              message: 'Pengeluaran yang dicatat di sini otomatis masuk laporan.',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < expenses.length; index++) ...[
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF1F2),
                        child: Icon(Icons.remove_circle_outline_rounded,
                            color: AppTheme.danger),
                      ),
                      title: Text(expenses[index].category,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        '${expenses[index].description ?? 'Tanpa keterangan'}\n${DateFormat('d MMM y', 'id_ID').format(expenses[index].occurredAt.toLocal())}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_rupiah(expenses[index].amount),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(
                            tooltip: 'Ubah pengeluaran',
                            onPressed: () => onEdit(expenses[index]),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                    if (index < expenses.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
        ],
      );
}

class _PromotionDataPanel extends StatelessWidget {
  const _PromotionDataPanel({
    required this.promotions,
    required this.products,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<_OwnerScheduledPromotion> promotions;
  final List<_OwnerProduct> products;
  final VoidCallback onAdd;
  final ValueChanged<_OwnerScheduledPromotion> onEdit;
  final ValueChanged<_OwnerScheduledPromotion> onDelete;

  @override
  Widget build(BuildContext context) {
    final productNames = {for (final product in products) product.id: product.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          title: 'Promo terjadwal',
          subtitle:
              'Atur Happy Hour. Harga promo berlaku otomatis di kasir pada jam yang dipilih.',
          actionLabel: 'Buat promo',
          actionIcon: Icons.add_alarm_rounded,
          onAction: products.isEmpty ? () {} : onAdd,
        ),
        if (products.isEmpty) ...[
          const SizedBox(height: 12),
          const _OwnerOperationsEmpty(
            icon: Icons.restaurant_menu_outlined,
            title: 'Tambahkan menu dulu',
            message: 'Promo dibuat untuk menu yang sudah tersedia.',
          ),
        ] else ...[
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFFFFBEB),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kasir memakai satu promo saja per menu. Bila jadwal bertabrakan, promo yang terakhir disimpan yang dipakai. Harga item yang sudah masuk keranjang tetap terkunci.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (promotions.isEmpty)
            const _OwnerOperationsEmpty(
              icon: Icons.schedule_outlined,
              title: 'Belum ada promo aktif',
              message: 'Contoh: Happy Hour 08.00–11.00 untuk Kopi Susu.',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < promotions.length; index++) ...[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.warning.withValues(alpha: .12),
                        child: const Icon(Icons.local_offer_outlined,
                            color: AppTheme.warning),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(promotions[index].name,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          _StatusPill(
                            label: promotions[index].isActive ? 'Aktif' : 'Nonaktif',
                            active: promotions[index].isActive,
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_promotionScheduleLabel(promotions[index])} · '
                          '${_timeOfDayLabel(promotions[index].startTime)}–${_timeOfDayLabel(promotions[index].endTime)}\n'
                          '${_promotionProductsLabel(promotions[index], productNames)}',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Ubah promo',
                            onPressed: () => onEdit(promotions[index]),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Hapus promo',
                            onPressed: () => onDelete(promotions[index]),
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.danger),
                          ),
                        ],
                      ),
                    ),
                    if (index < promotions.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          );
          final action = FilledButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
          );
          if (constraints.maxWidth < 580) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 12), action],
            );
          }
          return Row(children: [Expanded(child: heading), action]);
        },
      );
}

class _CategoryEditor extends StatefulWidget {
  final _OwnerCategory? category;
  final Future<void> Function({
    required _OwnerCategory? category,
    required String name,
    required String colorHex,
    required bool isActive,
  }) onSave;

  const _CategoryEditor({required this.category, required this.onSave});

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name;
  late String _colorHex;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  String get _selectedColorName {
    for (final color in _categoryColorPalette) {
      if (color.hex == _colorHex) return color.name;
    }
    return 'Warna tersimpan';
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _colorHex = widget.category?.colorHex.toUpperCase() ?? '#356B66';
    _isActive = widget.category?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama kategori wajib diisi.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        category: widget.category,
        name: name,
        colorHex: _colorHex,
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) {
        setState(() => _error = 'Kategori belum dapat disimpan. Coba lagi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kategori belum dapat disimpan. Periksa koneksi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.category == null ? 'Tambah kategori' : 'Ubah kategori'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama kategori'),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Warna kategori',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in _categoryColorPalette)
                      Tooltip(
                        message: color.name,
                        child: Semantics(
                          button: true,
                          selected: _colorHex == color.hex,
                          label: 'Warna ${color.name}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: _saving
                                ? null
                                : () => setState(() => _colorHex = color.hex),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _colorFromHex(color.hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _colorHex == color.hex
                                      ? AppTheme.textPrimary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: _colorHex == color.hex
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: _colorFromHex(color.hex)
                                                  .computeLuminance() >
                                              .55
                                          ? Colors.black
                                          : Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedColorName,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kategori aktif'),
                  subtitle: const Text('Kategori nonaktif disembunyikan dari kasir.'),
                  value: _isActive,
                  onChanged: _saving ? null : (value) => setState(() => _isActive = value),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      );
}

class _ProductEditor extends StatefulWidget {
  final _OwnerProduct? product;
  final List<_OwnerCategory> categories;
  final Future<void> Function({
    required _OwnerProduct? product,
    required String? categoryId,
    required String name,
    required String? description,
    required String price,
    required String cogs,
    required bool isAvailable,
    required bool trackStock,
    required String stock,
    required String lowStockAlert,
  }) onSave;

  const _ProductEditor({
    required this.product,
    required this.categories,
    required this.onSave,
  });

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _cogs;
  late final TextEditingController _stock;
  late final TextEditingController _lowStockAlert;
  String? _categoryId;
  late bool _isAvailable;
  late bool _trackStock;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _description = TextEditingController(text: widget.product?.description ?? '');
    _price = TextEditingController(text: widget.product?.price ?? '');
    _cogs = TextEditingController(text: widget.product?.cogs ?? '0');
    _stock = TextEditingController(text: widget.product?.stock ?? '0');
    _lowStockAlert =
        TextEditingController(text: widget.product?.lowStockAlert ?? '5');
    _categoryId = widget.categories.any((item) => item.id == widget.product?.categoryId)
        ? widget.product?.categoryId
        : null;
    _isAvailable = widget.product?.isAvailable ?? true;
    _trackStock = widget.product?.trackStock ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _cogs.dispose();
    _stock.dispose();
    _lowStockAlert.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = _validNumber(_price.text, allowZero: false);
    final cogs = _validNumber(_cogs.text);
    final stock = _validNumber(_stock.text);
    final lowStock = _validNumber(_lowStockAlert.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Nama menu wajib diisi.');
      return;
    }
    if (price == null || cogs == null || stock == null || lowStock == null) {
      setState(() => _error = 'Harga, HPP, dan stok harus berupa angka valid.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        product: widget.product,
        categoryId: _categoryId,
        name: _name.text,
        description: _description.text,
        price: price,
        cogs: cogs,
        isAvailable: _isAvailable,
        trackStock: _trackStock,
        stock: stock,
        lowStockAlert: lowStock,
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) setState(() => _error = 'Menu belum dapat disimpan. Coba lagi.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Menu belum dapat disimpan. Periksa koneksi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'Tambah menu' : 'Ubah menu'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama menu'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Tanpa kategori'),
                    ),
                    ...widget.categories.map((category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        )),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi (opsional)',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _price,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Harga jual'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _cogs,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'HPP'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Menu tersedia'),
                  subtitle: const Text('Matikan untuk menyembunyikan menu dari kasir.'),
                  value: _isAvailable,
                  onChanged: _saving ? null : (value) => setState(() => _isAvailable = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lacak stok'),
                  subtitle: widget.product == null
                      ? null
                      : Text(
                          _trackStock
                              ? 'Mode stok dikunci dari dashboard agar transaksi perangkat offline tidak terlewat.'
                              : 'Mode stok hanya dapat ditentukan saat menu dibuat dari dashboard.',
                        ),
                  value: _trackStock,
                  onChanged: widget.product == null && !_saving
                      ? (value) => setState(() => _trackStock = value)
                      : null,
                ),
                if (widget.product != null && _trackStock)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Gunakan tombol stok pada daftar menu untuk melakukan penyesuaian stok dengan aman.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                if (_trackStock)
                  Row(
                    children: [
                      if (widget.product == null) ...[
                        Expanded(
                          child: TextField(
                            controller: _stock,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Stok awal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _lowStockAlert,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Batas stok rendah'),
                        ),
                      ),
                    ],
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan menu'),
          ),
        ],
      );
}

class _StockConflictException implements Exception {
  final String? currentStock;
  const _StockConflictException(this.currentStock);
}

class _StockAdjustmentDialog extends StatefulWidget {
  final _OwnerProduct product;
  final Future<void> Function(String stock) onSave;

  const _StockAdjustmentDialog({
    required this.product,
    required this.onSave,
  });

  @override
  State<_StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  late final TextEditingController _stock;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stock = TextEditingController(text: _numberLabel(widget.product.stock));
  }

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final stock = _validNumber(_stock.text);
    if (stock == null) {
      setState(() => _error = 'Stok harus berupa angka nol atau lebih.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(stock);
      if (mounted) Navigator.of(context).pop();
    } on _StockConflictException catch (_) {
      if (mounted) {
        setState(() => _error =
            'Stok berubah karena sinkronisasi transaksi. Data terbaru sudah dimuat; periksa lalu simpan kembali.');
      }
    } on PostgrestException {
      if (mounted) {
        setState(() => _error = 'Stok belum dapat disimpan. Coba lagi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Stok belum dapat disimpan. Periksa koneksi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Sesuaikan stok ${widget.product.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stok server saat ini: ${_numberLabel(widget.product.stock)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gunakan jumlah fisik terbaru. Jika perangkat lain sedang menyinkronkan transaksi, sistem akan menolak data lama agar stok tidak tertimpa.',
                  style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _stock,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Stok fisik terbaru',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan stok'),
          ),
        ],
      );
}

class _TableEditor extends StatefulWidget {
  final _OwnerTable? table;
  final Future<void> Function({
    required _OwnerTable? table,
    required String label,
    required String? area,
    required int capacity,
  }) onSave;

  const _TableEditor({required this.table, required this.onSave});

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late final TextEditingController _label;
  late final TextEditingController _area;
  late final TextEditingController _capacity;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.table?.label ?? '');
    _area = TextEditingController(text: widget.table?.area ?? '');
    _capacity = TextEditingController(text: '${widget.table?.capacity ?? 4}');
  }

  @override
  void dispose() {
    _label.dispose();
    _area.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final capacity = int.tryParse(_capacity.text.trim());
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Label meja wajib diisi.');
      return;
    }
    if (capacity == null || capacity < 1 || capacity > 100) {
      setState(() => _error = 'Kapasitas harus antara 1 sampai 100.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        table: widget.table,
        label: _label.text,
        area: _area.text,
        capacity: capacity,
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) setState(() => _error = 'Meja belum dapat disimpan. Coba lagi.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Meja belum dapat disimpan. Periksa koneksi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.table == null ? 'Tambah meja' : 'Ubah meja'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _label,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Label meja'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _area,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Area (opsional)',
                    hintText: 'Contoh: Lantai 1',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kapasitas kursi'),
                ),
                if (widget.table != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Status meja yang sedang dipakai kasir tidak diubah dari dashboard.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan meja'),
          ),
        ],
      );
}

class _ExpenseEditor extends StatefulWidget {
  final _OwnerExpense? expense;
  final Future<void> Function({
    required _OwnerExpense? expense,
    required String category,
    required String? description,
    required String amount,
    required DateTime occurredAt,
  }) onSave;

  const _ExpenseEditor({required this.expense, required this.onSave});

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late DateTime _occurredAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = TextEditingController(text: widget.expense?.category ?? 'Operasional');
    _description = TextEditingController(text: widget.expense?.description ?? '');
    _amount = TextEditingController(text: widget.expense?.amount ?? '');
    _occurredAt = widget.expense?.occurredAt.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    _category.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Tanggal pengeluaran',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) setState(() => _occurredAt = picked);
  }

  Future<void> _submit() async {
    final amount = _validNumber(_amount.text, allowZero: false);
    if (_category.text.trim().isEmpty) {
      setState(() => _error = 'Kategori pengeluaran wajib diisi.');
      return;
    }
    if (amount == null) {
      setState(() => _error = 'Nominal pengeluaran harus lebih dari 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        expense: widget.expense,
        category: _category.text,
        description: _description.text,
        amount: amount,
        occurredAt: _occurredAt,
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) {
        setState(() => _error = 'Pengeluaran belum dapat disimpan. Coba lagi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pengeluaran belum dapat disimpan. Periksa koneksi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.expense == null ? 'Catat pengeluaran' : 'Ubah pengeluaran'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _category,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Nominal'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (opsional)',
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(DateFormat('d MMMM y', 'id_ID').format(_occurredAt)),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      );
}

class _PromotionEditor extends StatefulWidget {
  const _PromotionEditor({
    required this.promotion,
    required this.products,
    required this.onSave,
  });

  final _OwnerScheduledPromotion? promotion;
  final List<_OwnerProduct> products;
  final Future<void> Function({
    required _OwnerScheduledPromotion? promotion,
    required String name,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required Set<int> activeWeekdays,
    required String scheduleMode,
    required DateTime? startDate,
    required DateTime? endDate,
    required bool isActive,
    required List<_OwnerPromotionItemDraft> items,
  }) onSave;

  @override
  State<_PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends State<_PromotionEditor> {
  late final TextEditingController _name;
  final Map<String, TextEditingController> _promoPrices = {};
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Set<int> _activeWeekdays;
  late String _scheduleMode;
  late DateTime? _startDate;
  late DateTime? _endDate;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.promotion?.name ?? 'Happy Hour');
    _startTime = widget.promotion?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
    _endTime = widget.promotion?.endTime ?? const TimeOfDay(hour: 11, minute: 0);
    _activeWeekdays = Set<int>.from(
      widget.promotion?.activeWeekdays ?? const {1, 2, 3, 4, 5, 6, 7},
    );
    _scheduleMode = widget.promotion?.scheduleMode ?? 'WEEKLY';
    _startDate = widget.promotion?.startDate;
    _endDate = widget.promotion?.endDate;
    _isActive = widget.promotion?.isActive ?? true;
    for (final item in widget.promotion?.items ?? const <_OwnerPromotionItem>[]) {
      _promoPrices[item.productId] = TextEditingController(
        text: _numberLabel(item.promoPrice.toString()),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _promoPrices.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _startMinutes => _startTime.hour * 60 + _startTime.minute;
  int get _endMinutes => _endTime.hour * 60 + _endTime.minute;

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      helpText: start ? 'Jam mulai promo' : 'Jam selesai promo',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
    final firstDate = DateTime(now.year - 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 5),
      helpText: start ? 'Tanggal mulai promo' : 'Tanggal selesai promo',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }

  void _toggleProduct(_OwnerProduct product, bool selected) {
    setState(() {
      if (selected) {
        _promoPrices.putIfAbsent(
          product.id,
          () => TextEditingController(text: _numberLabel(product.price)),
        );
      } else {
        _promoPrices.remove(product.id)?.dispose();
      }
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama promo wajib diisi.');
      return;
    }
    if (_scheduleMode == 'WEEKLY' && _activeWeekdays.isEmpty) {
      setState(() => _error = 'Pilih minimal satu hari promo.');
      return;
    }
    if (_scheduleMode == 'DATE_RANGE' &&
        (_startDate == null || _endDate == null || _endDate!.isBefore(_startDate!))) {
      setState(() => _error = 'Pilih rentang tanggal promo yang valid.');
      return;
    }
    if (_endMinutes <= _startMinutes) {
      setState(() => _error = 'Jam selesai harus setelah jam mulai.');
      return;
    }
    if (_promoPrices.isEmpty) {
      setState(() => _error = 'Pilih minimal satu menu untuk promo ini.');
      return;
    }

    final productsById = {for (final product in widget.products) product.id: product};
    final items = <_OwnerPromotionItemDraft>[];
    for (final entry in _promoPrices.entries) {
      final product = productsById[entry.key];
      final promoPrice = _parseNumber(entry.value.text);
      final regularPrice = product == null ? null : _parseNumber(product.price);
      if (promoPrice == null || regularPrice == null || promoPrice >= regularPrice) {
        setState(() {
          _error = product == null
              ? 'Salah satu menu promo sudah tidak tersedia. Tutup lalu buka ulang data.'
              : 'Harga promo ${product.name} harus lebih rendah dari harga normal.';
        });
        return;
      }
      // [regularPrice] can only be non-null when this local lookup succeeded.
      final selectedProduct = product!;
      items.add(_OwnerPromotionItemDraft(
        productId: selectedProduct.id,
        promoPrice: promoPrice,
      ));
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        promotion: widget.promotion,
        name: name,
        startTime: _startTime,
        endTime: _endTime,
        activeWeekdays: _activeWeekdays,
        scheduleMode: _scheduleMode,
        startDate: _startDate,
        endDate: _endDate,
        isActive: _isActive,
        items: items,
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = _promotionSaveError(
              error,
              scheduleMode: _scheduleMode,
            ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Promo belum dapat disimpan. Periksa koneksi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.promotion == null ? 'Buat promo terjadwal' : 'Ubah promo'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama promo',
                    hintText: 'Contoh: Happy Hour Pagi',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Jenis jadwal',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(_scheduleMode),
                  initialValue: _scheduleMode,
                  decoration: const InputDecoration(
                    labelText: 'Berlaku sebagai',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'WEEKLY',
                      child: Text('Berulang setiap minggu'),
                    ),
                    DropdownMenuItem(
                      value: 'DATE_RANGE',
                      child: Text('Periode tanggal tertentu'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _scheduleMode = value;
                            if (value == 'WEEKLY') {
                              _startDate = null;
                              _endDate = null;
                            }
                          });
                        },
                ),
                const SizedBox(height: 16),
                const Text('Jam berlaku',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickTime(start: true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Mulai ${_timeOfDayLabel(_startTime)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickTime(start: false),
                      icon: const Icon(Icons.stop_rounded),
                      label: Text('Selesai ${_timeOfDayLabel(_endTime)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_scheduleMode == 'WEEKLY') ...[
                  const Text('Hari berlaku',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final day in _promotionWeekdays)
                        FilterChip(
                          label: Text(day.shortLabel),
                          selected: _activeWeekdays.contains(day.weekday),
                          onSelected: _saving
                              ? null
                              : (selected) => setState(() {
                                    if (selected) {
                                      _activeWeekdays.add(day.weekday);
                                    } else {
                                      _activeWeekdays.remove(day.weekday);
                                    }
                                  }),
                        ),
                    ],
                  ),
                ] else ...[
                  const Text('Periode promo',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Promo aktif setiap hari dalam rentang ini, lalu otomatis berhenti.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(start: true),
                        icon: const Icon(Icons.event_outlined),
                        label: Text('Mulai ${_dateLabel(_startDate)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(start: false),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('Selesai ${_dateLabel(_endDate)}'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: _saving ? null : (value) => setState(() => _isActive = value),
                  title: const Text('Promo aktif'),
                  subtitle: const Text('Promo nonaktif tersimpan, tetapi tidak dipakai kasir.'),
                ),
                const SizedBox(height: 8),
                const Text('Menu dan harga promo',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                  'Harga promo berlaku untuk harga dasar menu. Tambahan varian tetap ditambahkan seperti biasa.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final product in widget.products)
                  _PromotionProductRow(
                    product: product,
                    controller: _promoPrices[product.id],
                    enabled: !_saving,
                    onSelected: (selected) => _toggleProduct(product, selected),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan promo'),
          ),
        ],
      );
}

class _PromotionProductRow extends StatelessWidget {
  const _PromotionProductRow({
    required this.product,
    required this.controller,
    required this.enabled,
    required this.onSelected,
  });

  final _OwnerProduct product;
  final TextEditingController? controller;
  final bool enabled;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 8),
        decoration: BoxDecoration(
          color: controller == null ? AppTheme.surface : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: controller != null,
              onChanged: enabled ? (value) => onSelected(value ?? false) : null,
              title: Text(product.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('Harga normal ${_rupiah(product.price)}',
                  style: const TextStyle(fontSize: 11)),
            ),
            if (controller != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [
                    NormalizedNumberInputFormatter(allowDecimal: true),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Harga promo',
                    prefixText: 'Rp ',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _PromotionWeekday {
  const _PromotionWeekday(this.weekday, this.shortLabel, this.label);
  final int weekday;
  final String shortLabel;
  final String label;
}

const _promotionWeekdays = <_PromotionWeekday>[
  _PromotionWeekday(1, 'Sen', 'Senin'),
  _PromotionWeekday(2, 'Sel', 'Selasa'),
  _PromotionWeekday(3, 'Rab', 'Rabu'),
  _PromotionWeekday(4, 'Kam', 'Kamis'),
  _PromotionWeekday(5, 'Jum', 'Jumat'),
  _PromotionWeekday(6, 'Sab', 'Sabtu'),
  _PromotionWeekday(7, 'Min', 'Minggu'),
];

class _OperationsPageShell extends StatelessWidget {
  final Widget child;
  const _OperationsPageShell({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.surface,
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 40),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: child,
            ),
          ),
        ),
      );
}

class _OwnerOperationsEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _OwnerOperationsEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: AppTheme.primary),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary)),
                if (action != null) ...[const SizedBox(height: 18), action!],
              ],
            ),
          ),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;
  const _StatusPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (active ? AppTheme.success : AppTheme.textSecondary)
              .withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? AppTheme.success : AppTheme.textSecondary,
            )),
      );
}

String? _emptyToNull(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

double? _parseNumber(String input) {
  var normalized = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty || normalized.startsWith('-')) return null;
  normalized = normalized.replaceFirst(RegExp(r'^[Rr][Pp]'), '');
  normalized = normalized.replaceAll(RegExp(r'[^0-9,.]'), '');
  if (normalized.isEmpty) return null;

  final lastDot = normalized.lastIndexOf('.');
  final lastComma = normalized.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    // The last separator is the decimal separator; the other one is a
    // thousands separator (for example 1.234,56 or 1,234.56).
    final decimalSeparator = lastDot > lastComma ? '.' : ',';
    final groupingSeparator = decimalSeparator == '.' ? ',' : '.';
    normalized = normalized.replaceAll(groupingSeparator, '');
    normalized = normalized.replaceFirst(decimalSeparator, '.');
  } else if (lastDot >= 0 || lastComma >= 0) {
    final separator = lastDot >= 0 ? '.' : ',';
    final parts = normalized.split(separator);
    final hasGroupedThousands = parts.length > 2 ||
        (parts.length == 2 &&
            parts[1].length == 3 &&
            parts[0].isNotEmpty);
    if (hasGroupedThousands) {
      normalized = parts.join();
    } else {
      normalized = normalized.replaceFirst(separator, '.');
    }
  }

  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

bool _isMissingPromotionScheduleRpc(PostgrestException error) {
  final code = error.code?.toUpperCase() ?? '';
  final message = error.message.toLowerCase();
  return code == 'PGRST202' && message.contains('upsert_scheduled_promotion');
}

String _promotionSaveError(
  PostgrestException error, {
  required String scheduleMode,
}) {
  final code = error.code?.toUpperCase() ?? '';
  final details = '${error.message} ${error.details ?? ''}'.toLowerCase();
  if (scheduleMode == 'DATE_RANGE' &&
      (code == 'PGRST202' || details.contains('upsert_scheduled_promotion'))) {
    return 'Promo tanggal belum aktif di Cloud. Jalankan migration promo terbaru di Supabase lalu coba lagi.';
  }
  if (details.contains('promotion_price_not_lower')) {
    return 'Harga promo harus lebih rendah dari harga normal menu.';
  }
  if (details.contains('promotion_product_invalid')) {
    return 'Data harga salah satu menu belum valid. Buka ulang data menu lalu coba lagi.';
  }
  return 'Promo belum dapat disimpan. Periksa koneksi atau coba lagi.';
}

String? _validNumber(String input, {bool allowZero = true}) {
  final value = _parseNumber(input);
  if (value == null || (!allowZero && value == 0)) return null;
  return value.toString();
}

int _asInt(dynamic value, {required int fallback}) => value is int
    ? value
    : int.tryParse(value?.toString() ?? '') ?? fallback;

String _numberLabel(String value) {
  final number = _parseNumber(value) ?? 0;
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _rupiah(String value) => NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(double.tryParse(value) ?? 0);

Color _colorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  final color = int.tryParse(normalized, radix: 16);
  return color == null ? AppTheme.primary : Color(0xFF000000 | color);
}

String _tableStatusLabel(String status) => switch (status) {
      'occupied' => 'Terisi',
      'reserved' => 'Dipesan',
      'cleaning' => 'Dibersihkan',
      _ => 'Tersedia',
    };

TimeOfDay _timeOfDayFromSql(String? raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw?.trim() ?? '');
  final hour = int.tryParse(match?.group(1) ?? '');
  final minute = int.tryParse(match?.group(2) ?? '');
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return const TimeOfDay(hour: 0, minute: 0);
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _timeOfDaySql(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

String? _dateOnlySql(DateTime? date) => date == null
    ? null
    : '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

DateTime? _dateOnlyFromSql(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

String _dateLabel(DateTime? date) => date == null
    ? 'Pilih tanggal'
    : DateFormat('d MMM yyyy', 'id_ID').format(date);

String _timeOfDayLabel(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')}';

Set<int> _weekdaysFromJson(dynamic raw) {
  final Iterable<dynamic> values;
  if (raw is Iterable) {
    values = raw.cast<dynamic>();
  } else if (raw is String) {
    values = raw
        .replaceAll(RegExp(r'[\[\]{}]'), '')
        .split(',')
        .where((value) => value.trim().isNotEmpty);
  } else {
    values = const <dynamic>[];
  }
  final days = values
      .map((value) => int.tryParse(value.toString()))
      .whereType<int>()
      .where((value) => value >= 1 && value <= 7)
      .toSet();
  return days.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : days;
}

String _weekdayLabel(Set<int> days) {
  if (days.length == 7) return 'Setiap hari';
  return _promotionWeekdays
      .where((weekday) => days.contains(weekday.weekday))
      .map((weekday) => weekday.shortLabel)
      .join(', ');
}

String _promotionScheduleLabel(_OwnerScheduledPromotion promotion) {
  if (promotion.scheduleMode == 'DATE_RANGE' &&
      promotion.startDate != null &&
      promotion.endDate != null) {
    return '${_dateLabel(promotion.startDate)}–${_dateLabel(promotion.endDate)}';
  }
  return _weekdayLabel(promotion.activeWeekdays);
}

String _promotionProductsLabel(
  _OwnerScheduledPromotion promotion,
  Map<String, String> productNames,
) {
  if (promotion.items.isEmpty) return 'Tidak ada menu';
  final labels = promotion.items
      .map((item) {
        final name = productNames[item.productId] ?? 'Menu dihapus';
        return '$name ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(item.promoPrice)}';
      })
      .toList(growable: false);
  if (labels.length <= 2) return labels.join(' · ');
  return '${labels.take(2).join(' · ')} +${labels.length - 2} menu';
}

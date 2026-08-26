import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../core/numeric_input_formatter.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../domain/product_variant_options.dart';
import '../shared/polish_widgets.dart';
import '../shared/product_image.dart';

class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProductTab = _tabController.index == 0;
    final currentUser = ref.watch(currentUserProvider);
    final canManageMenu = currentUser?.canManageOperations == true;
    final canDeleteMenu = currentUser?.isOwner == true;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Menu & Produk'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Produk'),
            Tab(text: 'Kategori'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: AppTheme.primary,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ProductTab(
              search: _search,
              canManage: canManageMenu,
              canDelete: canDeleteMenu,
              onSearchChanged: (v) => setState(() => _search = v)),
          _CategoryTab(
            canManage: canManageMenu,
            canDelete: canDeleteMenu,
          ),
        ],
      ),
      floatingActionButton: canManageMenu
          ? FloatingActionButton.extended(
              onPressed: () => isProductTab
                  ? _openProductForm(context, ref)
                  : _openCategoryForm(context, ref),
              backgroundColor: AppTheme.action,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                isProductTab ? 'Tambah Produk' : 'Tambah Kategori',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  void _openProductForm(BuildContext ctx, WidgetRef ref, [Product? product]) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(product: product),
    );
  }

  void _openCategoryForm(BuildContext ctx, WidgetRef ref,
      [Category? category]) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryFormSheet(category: category),
    );
  }
}

// ── PRODUCT TAB ───────────────────────────────────────────────
class _ProductTab extends ConsumerWidget {
  final String search;
  final bool canManage;
  final bool canDelete;
  final ValueChanged<String> onSearchChanged;

  const _ProductTab({
    required this.search,
    required this.canManage,
    required this.canDelete,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(allProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      children: [
        const ModernHeroHeader(
          title: 'Kelola Menu',
          subtitle:
              'Tambah produk, atur kategori, dan kontrol item yang tampil di kasir.',
          icon: Icons.menu_book_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.subtleBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.subtleBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
        ),

        // Product list
        Expanded(
          child: productsAsync.when(
            data: (products) {
              final filtered = search.isEmpty
                  ? products
                  : products
                      .where((p) =>
                          p.name.toLowerCase().contains(search.toLowerCase()))
                      .toList();

              if (filtered.isEmpty) {
                return EmptyStateView(
                  icon: Icons.fastfood_outlined,
                  title: search.isNotEmpty
                      ? 'Produk tidak ditemukan'
                      : 'Belum ada produk',
                  subtitle: search.isNotEmpty
                      ? 'Coba kata kunci lain atau cek nama produk.'
                      : 'Tambah produk pertama supaya tampil di kasir.',
                );
              }

              return categoriesAsync.when(
                data: (cats) {
                  final catMap = {for (final c in cats) c.id: c.name};
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ProductTile(
                      product: filtered[i],
                      categoryName: catMap[filtered[i].categoryId],
                      canManage: canManage,
                      canDelete: canDelete,
                    ),
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => ErrorStateView(
                  title: 'Kategori belum bisa dimuat',
                  onRetry: () => ref.invalidate(categoriesProvider),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => ErrorStateView(
              title: 'Produk belum bisa dimuat',
              onRetry: () => ref.invalidate(allProductsProvider),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductTile extends ConsumerWidget {
  final Product product;
  final String? categoryName;
  final bool canManage;
  final bool canDelete;

  const _ProductTile({
    required this.product,
    this.categoryName,
    required this.canManage,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = double.tryParse(product.price) ?? 0;
    final stock = double.tryParse(product.stock) ?? 0;
    final lowStockAlert = double.tryParse(product.lowStockAlert) ?? 5;
    final isLowStock = product.trackStock && stock <= lowStockAlert;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.subtleBorder),
        boxShadow: AppTheme.softShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: ProductImage(
            source: product.imageUrl,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            fallback: _imgPlaceholder(),
          ),
        ),
        title: Text(product.name,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (categoryName != null)
              Text(categoryName!,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            Text(price.toRupiah,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
            if (product.trackStock)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLowStock
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined,
                      size: AppTheme.iconCompact,
                      color: isLowStock ? AppTheme.danger : AppTheme.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Sisa stok: ${_formatStock(stock)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isLowStock ? AppTheme.danger : AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: canManage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: product.isAvailable,
                    activeThumbColor: AppTheme.success,
                    onChanged: (v) {
                      ref
                          .read(databaseProvider)
                          .productDao
                          .toggleAvailability(product.id, v);
                    },
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Aksi produk',
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Color(0xFF6B7280)),
                    onSelected: (action) {
                      if (action == 'edit') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => ProductFormSheet(product: product),
                        );
                      } else if (action == 'stock') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              StockAdjustmentSheet(product: product),
                        );
                      } else if (action == 'delete') {
                        _confirmDelete(context, ref);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit produk'),
                        ),
                      ),
                      if (product.trackStock)
                        const PopupMenuItem(
                          value: 'stock',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.inventory_2_outlined),
                            title: Text('Atur stok'),
                          ),
                        ),
                      if (canDelete)
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline,
                                color: AppTheme.danger),
                            title: Text('Hapus produk',
                                style: TextStyle(color: AppTheme.danger)),
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : _AvailabilityPill(isAvailable: product.isAvailable),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (ref.read(currentUserProvider)?.isOwner != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Hanya owner yang dapat menghapus produk.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text(
          '${product.name} akan dihapus dari menu. Riwayat transaksi yang sudah tersimpan tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db = ref.read(databaseProvider);
    await db.syncDao.enqueue(
      tableName: 'products',
      recordId: product.id,
      operation: 'delete',
      payload: {
        'product_id': product.id,
        'outlet_id': product.outletId,
      },
    );
    await db.productDao.deleteProduct(product.id);

    final imagePath = product.imageUrl;
    if (imagePath != null && !imagePath.startsWith('http')) {
      try {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) await imageFile.delete();
      } catch (_) {
        // Penghapusan foto lokal tidak boleh menggagalkan penghapusan produk.
      }
    }

    await ref.read(syncServiceProvider).syncAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} berhasil dihapus.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  String _formatStock(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  Widget _imgPlaceholder() => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryLight, AppTheme.accentLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(Icons.fastfood_rounded,
            color: AppTheme.primary, size: 24),
      );
}

class StockAdjustmentSheet extends ConsumerStatefulWidget {
  final Product product;

  const StockAdjustmentSheet({super.key, required this.product});

  @override
  ConsumerState<StockAdjustmentSheet> createState() =>
      _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends ConsumerState<StockAdjustmentSheet> {
  late final TextEditingController _stockCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final currentStock = double.tryParse(widget.product.stock) ?? 0;
    _stockCtrl = TextEditingController(
      text: currentStock == currentStock.roundToDouble()
          ? currentStock.toInt().toString()
          : currentStock.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (ref.read(currentUserProvider)?.canManageOperations != true) return;
    final value = double.tryParse(_stockCtrl.text.trim().replaceAll(',', '.'));
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stok harus berupa angka 0 atau lebih.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    setState(() => _isSaving = true);
    final db = ref.read(databaseProvider);
    await db.productDao.updateStock(widget.product.id, value);
    await db.syncDao.enqueue(
      tableName: 'stock_sets',
      recordId: widget.product.id,
      operation: 'set',
      payload: {
        'outlet_id': widget.product.outletId,
        'stock': value,
      },
    );
    await ref.read(syncServiceProvider).syncAll();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: bottomSheetSafePadding(context),
        top: 8,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Atur Stok',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.product.name,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 18),
            const _FormLabel('Jumlah stok saat ini *'),
            TextField(
              controller: _stockCtrl,
              autofocus: true,
              selectAllOnFocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [
                NormalizedNumberInputFormatter(allowDecimal: true),
              ],
              decoration: InputDecoration(
                hintText: '0',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Simpan Stok'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.action,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CATEGORY TAB ──────────────────────────────────────────────
class _AvailabilityPill extends StatelessWidget {
  final bool isAvailable;
  const _AvailabilityPill({required this.isAvailable});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (isAvailable ? AppTheme.success : AppTheme.textSecondary)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          isAvailable ? 'Tersedia' : 'Nonaktif',
          style: TextStyle(
            color: isAvailable ? AppTheme.success : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _CategoryTab extends ConsumerWidget {
  final bool canManage;
  final bool canDelete;

  const _CategoryTab({
    required this.canManage,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      data: (cats) {
        if (cats.isEmpty) {
          return const EmptyStateView(
            icon: Icons.category_outlined,
            title: 'Belum ada kategori',
            subtitle: 'Buat kategori supaya menu lebih gampang dicari.',
          );
        }

        return ReorderableListView.builder(
          buildDefaultDragHandles: canManage,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: cats.length,
          onReorder: canManage
              ? (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) {
                    newIndex--;
                  }
                  final db = ref.read(databaseProvider);
                  // Update sort order
                  for (int i = 0; i < cats.length; i++) {
                    int newOrder = i;
                    if (i == oldIndex) {
                      newOrder = newIndex;
                    } else if (oldIndex < newIndex &&
                        i > oldIndex &&
                        i <= newIndex) {
                      newOrder = i - 1;
                    } else if (oldIndex > newIndex &&
                        i >= newIndex &&
                        i < oldIndex) {
                      newOrder = i + 1;
                    }
                    await db.productDao.upsertCategory(CategoriesCompanion(
                      id: Value(cats[i].id),
                      sortOrder: Value(newOrder),
                      updatedAt: Value(DateTime.now()),
                      isSynced: const Value(false),
                    ));
                  }
                }
              : (_, __) {},
          itemBuilder: (_, i) {
            final cat = cats[i];
            Color color;
            try {
              color = Color(int.parse(cat.colorHex.replaceFirst('#', '0xFF')));
            } catch (_) {
              color = AppTheme.primary;
            }

            return Container(
              key: ValueKey(cat.id),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.subtleBorder),
                boxShadow: AppTheme.softShadow,
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.label_rounded, color: color, size: 20),
                ),
                title: Text(cat.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: canManage
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            color: const Color(0xFF6B7280),
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CategoryFormSheet(category: cat),
                            ),
                          ),
                          if (canDelete)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: AppTheme.danger,
                              onPressed: () =>
                                  _confirmDeleteCategory(context, ref, cat),
                            ),
                          const Icon(Icons.drag_handle,
                              color: Color(0xFFD1D5DB)),
                        ],
                      )
                    : null,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => ErrorStateView(
        title: 'Kategori belum bisa dimuat',
        onRetry: () => ref.invalidate(categoriesProvider),
      ),
    );
  }

  Future<void> _confirmDeleteCategory(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    if (ref.read(currentUserProvider)?.isOwner != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          'Kategori ${category.name} akan dihapus. Produk di dalamnya tetap ada dan dipindahkan ke tanpa kategori.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(databaseProvider).productDao.deleteCategory(category.id);
    await ref.read(syncServiceProvider).syncAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Kategori ${category.name} berhasil dihapus.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }
}

// ── PRODUCT FORM SHEET ────────────────────────────────────────
class ProductFormSheet extends ConsumerStatefulWidget {
  final Product? product;
  const ProductFormSheet({super.key, this.product});

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _cogsCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _lowStockCtrl;
  String? _selectedCategoryId;
  String? _imagePath;
  bool _isAvailable = true;
  bool _trackStock = false;
  bool _isSaving = false;
  bool _loadingVariants = false;
  String? _variantLoadError;
  final List<_EditableVariantGroup> _variants = [];
  final Set<String> _originalVariantIds = {};

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(text: p?.price ?? '');
    _cogsCtrl = TextEditingController(
      text: p == null || p.cogs == '0' ? '' : p.cogs,
    );
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _stockCtrl = TextEditingController(
      text: p == null || p.stock == '0' ? '' : p.stock,
    );
    _lowStockCtrl = TextEditingController(
      text: p == null || p.lowStockAlert == '0' ? '' : p.lowStockAlert,
    );
    _imagePath = p?.imageUrl;
    _selectedCategoryId = p?.categoryId;
    _isAvailable = p?.isAvailable ?? true;
    _trackStock = p?.trackStock ?? false;
    if (p != null) _loadVariants(p.id);
  }

  Future<void> _loadVariants(String productId) async {
    setState(() {
      _loadingVariants = true;
      _variantLoadError = null;
    });
    try {
      final stored =
          await ref.read(databaseProvider).productDao.getVariants(productId);
      stored
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _variants
          ..clear()
          ..addAll(stored.map((variant) => _EditableVariantGroup(
                id: variant.id,
                name: variant.name,
                options: parseProductVariantOptionDetails(variant.options),
                isRequired: variant.isRequired,
              )));
        _originalVariantIds
          ..clear()
          ..addAll(stored.map((variant) => variant.id));
        _loadingVariants = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingVariants = false;
        _variantLoadError = 'Pilihan produk gagal dimuat.';
      });
    }
  }

  Future<void> _openVariantEditor([int? index]) async {
    final result = await showModalBottomSheet<_EditableVariantGroup>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VariantGroupEditorSheet(
        initial: index == null ? null : _variants[index],
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _variants.add(result);
      } else {
        _variants[index] = result;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _cogsCtrl.dispose();
    _descCtrl.dispose();
    _stockCtrl.dispose();
    _lowStockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      final appDirectory = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory(
        path.join(appDirectory.path, 'product_images'),
      );
      await imageDirectory.create(recursive: true);

      final pickedExtension = path.extension(picked.path).toLowerCase();
      final safeExtension = pickedExtension.isEmpty ? '.jpg' : pickedExtension;
      final permanentPath = path.join(
        imageDirectory.path,
        'product_${const Uuid().v4()}$safeExtension',
      );
      await File(picked.path).copy(permanentPath);

      if (mounted) setState(() => _imagePath = permanentPath);
    }
  }

  Future<void> _save() async {
    if (ref.read(currentUserProvider)?.canManageOperations != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kasir tidak memiliki akses mengubah menu.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    final variantNames = <String>{};
    for (final variant in _variants) {
      if (!variantNames.add(variant.name.trim().toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Grup pilihan "${variant.name}" dibuat lebih dari sekali.'),
          backgroundColor: AppTheme.danger,
        ));
        return;
      }
    }
    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final id = widget.product?.id ?? const Uuid().v4();

    try {
      await db.transaction(() async {
        await db.productDao.upsertProduct(ProductsCompanion(
          id: Value(id),
          outletId: Value(outletId),
          categoryId: Value(_selectedCategoryId),
          name: Value(_nameCtrl.text.trim()),
          price: Value(_priceCtrl.text.trim()),
          cogs: Value(
              _cogsCtrl.text.trim().isEmpty ? '0' : _cogsCtrl.text.trim()),
          description: Value(
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
          imageUrl: Value(_imagePath),
          isAvailable: Value(_isAvailable),
          trackStock: Value(_trackStock),
          stock: Value(_trackStock
              ? (_stockCtrl.text.trim().isEmpty
                  ? '0'
                  : _stockCtrl.text.trim().replaceAll(',', '.'))
              : (widget.product?.stock ?? '0')),
          lowStockAlert: Value(_trackStock
              ? (_lowStockCtrl.text.trim().isEmpty
                  ? '5'
                  : _lowStockCtrl.text.trim().replaceAll(',', '.'))
              : (widget.product?.lowStockAlert ?? '5')),
          updatedAt: Value(DateTime.now()),
          isSynced: const Value(false),
        ));

        final currentVariantIds =
            _variants.map((variant) => variant.id).toSet();
        for (final removedId
            in _originalVariantIds.difference(currentVariantIds)) {
          await db.syncDao.enqueue(
            tableName: 'product_variants',
            recordId: removedId,
            operation: 'delete',
            payload: {'product_id': id, 'outlet_id': outletId},
          );
          await db.productDao.deleteVariant(removedId);
        }
        for (final variant in _variants) {
          await db.productDao.upsertVariant(ProductVariantsCompanion(
            id: Value(variant.id),
            productId: Value(id),
            name: Value(variant.name.trim()),
            options: Value(encodeProductVariantOptionDetails(variant.options)),
            isRequired: Value(variant.isRequired),
            updatedAt: Value(DateTime.now()),
            isSynced: const Value(false),
          ));
        }

        if (_trackStock) {
          final stock = double.tryParse(
                _stockCtrl.text.trim().replaceAll(',', '.'),
              ) ??
              0;
          await db.syncDao.enqueue(
            tableName: 'stock_sets',
            recordId: id,
            operation: 'set',
            payload: {
              'outlet_id': outletId,
              'stock': stock,
            },
          );
        }
      });

      await ref.read(syncServiceProvider).syncAll();

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Produk gagal disimpan. Periksa data lalu coba lagi.'),
        backgroundColor: AppTheme.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: bottomSheetSafePadding(context),
        top: 8,
        left: 20,
        right: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                  child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),

              Text(_isEdit ? 'Edit Produk' : 'Tambah Produk',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _imagePath != null
                          ? AppTheme.primary
                          : AppTheme.borderColor,
                      width: _imagePath != null ? 1.5 : 1,
                    ),
                  ),
                  child: _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ProductImage(
                            source: _imagePath,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            fallback: const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppTheme.primary,
                                  size: 28),
                            ),
                            const SizedBox(height: 8),
                            const Text('Tambah Foto',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary)),
                            const SizedBox(height: 2),
                            const Text('Opsional — tap untuk pilih dari galeri',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                ),
              ),
              if (_imagePath != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => setState(() => _imagePath = null),
                    child: const Text('Hapus foto',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Nama
              const _FormLabel('Nama Produk *'),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco('Contoh: Es Teh Manis'),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 14),

              // Kategori
              const _FormLabel('Kategori'),
              categoriesAsync.when(
                data: (cats) => DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  decoration: _inputDeco('Pilih kategori'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Tanpa kategori')),
                    ...cats.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                ),
                loading: () => const SizedBox(height: 48),
                error: (_, __) => OutlinedButton.icon(
                  onPressed: () => ref.invalidate(categoriesProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Muat ulang kategori'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Harga
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FormLabel('Harga Jual *'),
                        TextFormField(
                          controller: _priceCtrl,
                          selectAllOnFocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            NormalizedNumberInputFormatter(),
                          ],
                          decoration: _inputDeco('0'),
                          validator: (v) {
                            if (v?.trim().isEmpty == true) return 'Wajib diisi';
                            if (double.tryParse(v!) == null) {
                              return 'Harus angka';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FormLabel('Harga Modal'),
                        TextFormField(
                          controller: _cogsCtrl,
                          selectAllOnFocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            NormalizedNumberInputFormatter(),
                          ],
                          decoration: _inputDeco('0'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Deskripsi
              const _FormLabel('Deskripsi'),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: _inputDeco('Deskripsi singkat (opsional)'),
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.subtleBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilihan & Modifier',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Contoh: Ukuran atau Extra Topping, termasuk tambahan harga.',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          tooltip: 'Tambah grup pilihan',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: _loadingVariants
                              ? null
                              : () => _openVariantEditor(),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                    if (_loadingVariants) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 3),
                    ] else if (_variantLoadError != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pilihan produk gagal dimuat.',
                              style: TextStyle(
                                color: AppTheme.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.product == null
                                ? null
                                : () => _loadVariants(widget.product!.id),
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      ),
                    ] else if (_variants.isEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Belum ada pilihan. Produk langsung masuk keranjang saat dipilih.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      ...List.generate(_variants.length, (index) {
                        final variant = _variants[index];
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.subtleBorder),
                          ),
                          child: ListTile(
                            minTileHeight: 58,
                            contentPadding:
                                const EdgeInsets.only(left: 12, right: 4),
                            title: Text(
                              variant.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${variant.options.map(_variantOptionLabel).join(', ')} - ${variant.isRequired ? 'Wajib' : 'Opsional'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit ${variant.name}',
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  onPressed: () => _openVariantEditor(index),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Hapus ${variant.name}',
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  color: AppTheme.danger,
                                  onPressed: () =>
                                      setState(() => _variants.removeAt(index)),
                                  icon:
                                      const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Toggle
              Row(
                children: [
                  Expanded(
                    child: _ToggleRow(
                      label: 'Tersedia',
                      subtitle: 'Tampil di kasir',
                      value: _isAvailable,
                      onChanged: (v) => setState(() => _isAvailable = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToggleRow(
                      label: 'Lacak Stok',
                      subtitle: 'Kurangi stok saat terjual',
                      value: _trackStock,
                      onChanged: (v) => setState(() => _trackStock = v),
                    ),
                  ),
                ],
              ),
              if (_trackStock) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FormLabel('Stok Awal / Sisa Stok *'),
                            TextFormField(
                              controller: _stockCtrl,
                              selectAllOnFocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: const [
                                NormalizedNumberInputFormatter(
                                  allowDecimal: true,
                                ),
                              ],
                              decoration: _inputDeco('0'),
                              validator: (value) {
                                if (!_trackStock) return null;
                                final raw = (value ?? '').trim();
                                final parsed = raw.isEmpty
                                    ? 0
                                    : double.tryParse(raw.replaceAll(',', '.'));
                                if (parsed == null || parsed < 0) {
                                  return 'Minimal 0';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FormLabel('Peringatan Stok Menipis'),
                            TextFormField(
                              controller: _lowStockCtrl,
                              selectAllOnFocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: const [
                                NormalizedNumberInputFormatter(
                                  allowDecimal: true,
                                ),
                              ],
                              decoration: _inputDeco('5'),
                              validator: (value) {
                                if (!_trackStock) return null;
                                final raw = (value ?? '').trim();
                                final parsed = raw.isEmpty
                                    ? 5
                                    : double.tryParse(raw.replaceAll(',', '.'));
                                if (parsed == null || parsed < 0) {
                                  return 'Minimal 0';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isSaving || _loadingVariants || _variantLoadError != null
                          ? null
                          : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.action,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Produk',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.danger)),
      );
}

// ── CATEGORY FORM SHEET ───────────────────────────────────────
class _EditableVariantGroup {
  const _EditableVariantGroup({
    required this.id,
    required this.name,
    required this.options,
    required this.isRequired,
  });

  final String id;
  final String name;
  final List<ProductVariantOption> options;
  final bool isRequired;
}

class _VariantGroupEditorSheet extends StatefulWidget {
  const _VariantGroupEditorSheet({this.initial});

  final _EditableVariantGroup? initial;

  @override
  State<_VariantGroupEditorSheet> createState() =>
      _VariantGroupEditorSheetState();
}

class _VariantGroupEditorSheetState extends State<_VariantGroupEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final _optionCtrl = TextEditingController();
  final _optionPriceCtrl = TextEditingController();
  late final List<ProductVariantOption> _options;
  late bool _isRequired;
  String? _optionError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _options = List<ProductVariantOption>.from(
      widget.initial?.options ?? const [],
    );
    _isRequired = widget.initial?.isRequired ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _optionCtrl.dispose();
    _optionPriceCtrl.dispose();
    super.dispose();
  }

  void _addOption() {
    final option = _optionCtrl.text.trim();
    if (option.isEmpty) {
      setState(() => _optionError = 'Tulis nama opsi terlebih dahulu.');
      return;
    }
    if (option.length > 60) {
      setState(() => _optionError = 'Nama opsi maksimal 60 karakter.');
      return;
    }
    if (_options
        .any((item) => item.name.toLowerCase() == option.toLowerCase())) {
      setState(() => _optionError = 'Opsi tersebut sudah ada.');
      return;
    }
    if (_options.length >= 20) {
      setState(() => _optionError = 'Maksimal 20 opsi per grup.');
      return;
    }
    setState(() {
      final rawPrice = _optionPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      final priceDelta = double.tryParse(rawPrice) ?? 0;
      if (priceDelta > 1000000000) {
        setState(
          () => _optionError = 'Tambahan harga maksimal Rp1 miliar.',
        );
        return;
      }
      _options.add(ProductVariantOption(
        name: option,
        priceDelta: priceDelta,
      ));
      _optionCtrl.clear();
      _optionPriceCtrl.clear();
      _optionError = null;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_options.isEmpty) {
      setState(() => _optionError = 'Tambahkan minimal satu opsi.');
      return;
    }
    Navigator.pop(
      context,
      _EditableVariantGroup(
        id: widget.initial?.id ?? const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        options: List.unmodifiable(_options),
        isRequired: _isRequired,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          bottomSheetSafePadding(context, extra: 16),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                widget.initial == null
                    ? 'Tambah Grup Pilihan'
                    : 'Edit Grup Pilihan',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Satu opsi dapat dipilih dari setiap grup. Tambahan harga bersifat opsional.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FormLabel('Nama Grup *'),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 50,
                        decoration: _variantInputDecoration(
                          'Contoh: Ukuran, Level Gula',
                        ),
                        validator: (value) => value?.trim().isEmpty == true
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.subtleBorder),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Wajib dipilih',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Kasir tidak bisa melanjutkan tanpa memilih opsi.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _isRequired,
                          onChanged: (value) =>
                              setState(() => _isRequired = value),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _FormLabel('Opsi *'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _optionCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: _variantInputDecoration(
                                'Contoh: Regular',
                              ).copyWith(errorText: _optionError),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _optionPriceCtrl,
                              selectAllOnFocus: true,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                NormalizedNumberInputFormatter(),
                              ],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addOption(),
                              decoration: _variantInputDecoration(
                                'Tambah harga',
                              ).copyWith(prefixText: 'Rp ', hintText: '0'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Tambah opsi',
                            constraints: const BoxConstraints(
                              minWidth: 52,
                              minHeight: 52,
                            ),
                            onPressed: _addOption,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_options.isEmpty)
                        const Text(
                          'Belum ada opsi.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      else
                        ...List.generate(_options.length, (index) {
                          final option = _options[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.subtleBorder),
                            ),
                            child: ListTile(
                              minTileHeight: 52,
                              title: Text(
                                option.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                option.priceDelta > 0
                                    ? '+${option.priceDelta.toRupiah}'
                                    : 'Tanpa tambahan harga',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: option.priceDelta > 0
                                      ? AppTheme.success
                                      : AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Hapus ${option.name}',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                color: AppTheme.danger,
                                onPressed: () => setState(() {
                                  _options.removeAt(index);
                                  _optionError = null;
                                }),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.action,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Simpan Grup Pilihan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _variantOptionLabel(ProductVariantOption option) => option.priceDelta > 0
    ? '${option.name} (+${option.priceDelta.toRupiah})'
    : option.name;

InputDecoration _variantInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );

class CategoryFormSheet extends ConsumerStatefulWidget {
  final Category? category;
  const CategoryFormSheet({super.key, this.category});

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  final _nameCtrl = TextEditingController();
  String _colorHex = '#356B66';
  bool _isSaving = false;

  final _colors = [
    '#356B66',
    '#6F9E98',
    '#746FA8',
    '#557FA3',
    '#2F7D64',
    '#C57843',
    '#C55252',
    '#8A6E82',
    '#68809B',
    '#73807C',
    '#9B776D',
    '#596C68',
    '#7D8FA8',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.category?.name ?? '';
    _colorHex = widget.category?.colorHex ?? '#356B66';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (ref.read(currentUserProvider)?.canManageOperations != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kasir tidak memiliki akses mengubah kategori.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final id = widget.category?.id ?? const Uuid().v4();

    await db.productDao.upsertCategory(CategoriesCompanion(
      id: Value(id),
      outletId: Value(outletId),
      name: Value(_nameCtrl.text.trim()),
      colorHex: Value(_colorHex),
      updatedAt: Value(DateTime.now()),
      isSynced: const Value(false),
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: bottomSheetSafePadding(context),
        top: 8,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2)),
            )),
            Text(widget.category != null ? 'Edit Kategori' : 'Tambah Kategori',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            const _FormLabel('Nama Kategori *'),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'Contoh: Minuman, Makanan',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.borderColor)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            const _FormLabel('Warna'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colors.map((hex) {
                final color = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                final selected = _colorHex == hex;
                return GestureDetector(
                  onTap: () => setState(() => _colorHex = hex),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.action,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        widget.category != null ? 'Simpan' : 'Tambah Kategori',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────
class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151))),
      );
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppTheme.success,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );
}

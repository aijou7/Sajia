import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../shared/polish_widgets.dart';

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
    final canManageMenu =
        ref.watch(currentUserProvider)?.canManageOperations == true;
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
              onSearchChanged: (v) => setState(() => _search = v)),
          _CategoryTab(canManage: canManageMenu),
        ],
      ),
      floatingActionButton: canManageMenu
          ? FloatingActionButton.extended(
              onPressed: () => isProductTab
                  ? _openProductForm(context, ref)
                  : _openCategoryForm(context, ref),
              backgroundColor: AppTheme.primary,
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
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(product: product),
    );
  }

  void _openCategoryForm(BuildContext ctx, WidgetRef ref,
      [Category? category]) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryFormSheet(category: category),
    );
  }
}

// ── PRODUCT TAB ───────────────────────────────────────────────
class _ProductTab extends ConsumerWidget {
  final String search;
  final bool canManage;
  final ValueChanged<String> onSearchChanged;

  const _ProductTab({
    required this.search,
    required this.canManage,
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
                    ),
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
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

  const _ProductTile({
    required this.product,
    this.categoryName,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = double.tryParse(product.price) ?? 0;

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
          child: product.imageUrl == null
              ? _imgPlaceholder()
              : (product.imageUrl!.startsWith('/') ||
                      product.imageUrl!.startsWith('file://')
                  ? Image.file(
                      File(_localImagePath(product.imageUrl!)),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgPlaceholder(),
                    )
                  : Image.network(
                      product.imageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgPlaceholder(),
                    )),
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
          ],
        ),
        trailing: canManage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle available
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
                  // Edit
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: const Color(0xFF6B7280),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ProductFormSheet(product: product),
                    ),
                  ),
                ],
              )
            : _AvailabilityPill(isAvailable: product.isAvailable),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryLight, AppTheme.goldLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(Icons.fastfood_rounded,
            color: AppTheme.primary, size: 24),
      );

  String _localImagePath(String rawPath) {
    if (rawPath.startsWith('file://')) return Uri.parse(rawPath).toFilePath();
    return rawPath;
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
  const _CategoryTab({required this.canManage});

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
                              backgroundColor: Colors.transparent,
                              builder: (_) => CategoryFormSheet(category: cat),
                            ),
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
      error: (e, _) => Center(child: Text('Error: $e')),
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
  String? _selectedCategoryId;
  String? _imagePath;
  bool _isAvailable = true;
  bool _trackStock = false;
  bool _isSaving = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(text: p?.price ?? '');
    _cogsCtrl = TextEditingController(text: p?.cogs ?? '0');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _imagePath = p?.imageUrl;
    _selectedCategoryId = p?.categoryId;
    _isAvailable = p?.isAvailable ?? true;
    _trackStock = p?.trackStock ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _cogsCtrl.dispose();
    _descCtrl.dispose();
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
      setState(() => _imagePath = picked.path);
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
    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final id = widget.product?.id ?? const Uuid().v4();

    await db.productDao.upsertProduct(ProductsCompanion(
      id: Value(id),
      outletId: Value(outletId),
      categoryId: Value(_selectedCategoryId),
      name: Value(_nameCtrl.text.trim()),
      price: Value(_priceCtrl.text.trim()),
      cogs: Value(_cogsCtrl.text.trim().isEmpty ? '0' : _cogsCtrl.text.trim()),
      description:
          Value(_descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
      imageUrl: Value(_imagePath),
      isAvailable: Value(_isAvailable),
      trackStock: Value(_trackStock),
      updatedAt: Value(DateTime.now()),
      isSynced: const Value(false),
    ));

    if (mounted) Navigator.pop(context);
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
                          child: Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
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
                error: (_, __) => const SizedBox(),
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
                          keyboardType: TextInputType.number,
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
                          keyboardType: TextInputType.number,
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
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
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
class CategoryFormSheet extends ConsumerStatefulWidget {
  final Category? category;
  const CategoryFormSheet({super.key, this.category});

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  final _nameCtrl = TextEditingController();
  String _colorHex = '#1B6CA8';
  bool _isSaving = false;

  final _colors = [
    '#1B6CA8',
    '#1A9E6A',
    '#F59E0B',
    '#DC2626',
    '#0EA5E9',
    '#2D9CDB',
    '#0F4C7A',
    '#07395F',
    '#EF9F27',
    '#059669',
    '#D97706',
    '#6B7280',
    '#0284C7',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.category?.name ?? '';
    _colorHex = widget.category?.colorHex ?? '#1B6CA8';
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
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
                backgroundColor: AppTheme.primary,
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
                  : Text(widget.category != null ? 'Simpan' : 'Tambah Kategori',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
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

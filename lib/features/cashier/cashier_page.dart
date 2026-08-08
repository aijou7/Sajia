import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/entities.dart';
import '../../domain/product_variant_options.dart';
import '../shared/polish_widgets.dart';
import '../shared/product_image.dart';
import 'cart_panel.dart';
import 'payment_sheet.dart';

class CashierPage extends ConsumerStatefulWidget {
  const CashierPage({super.key});

  @override
  ConsumerState<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends ConsumerState<CashierPage> {
  String? _selectedCategoryId;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 700;
    return isTablet ? _buildTablet() : _buildPhone();
  }

  Widget _buildTablet() => Scaffold(
        backgroundColor: AppTheme.surface,
        body: Row(children: [
          Expanded(
            flex: 6,
            child: Column(children: [
              _TopBar(),
              _CategoryBar(
                selected: _selectedCategoryId,
                onSelect: (id) => setState(() => _selectedCategoryId =
                    _selectedCategoryId == id ? null : id),
              ),
              _SearchBar(
                  ctrl: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase())),
              Expanded(
                  child: _MenuGrid(
                      categoryId: _selectedCategoryId,
                      searchQuery: _searchQuery,
                      onAdd: _addToCart)),
            ]),
          ),
          SizedBox(
            width: 340,
            child: CartPanel(onCheckout: _openPayment),
          ),
        ]),
      );

  Widget _buildPhone() {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(children: [
        _TopBar(),
        _CategoryBar(
          selected: _selectedCategoryId,
          onSelect: (id) => setState(() =>
              _selectedCategoryId = _selectedCategoryId == id ? null : id),
        ),
        _SearchBar(
            ctrl: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase())),
        Expanded(
            child: _MenuGrid(
                categoryId: _selectedCategoryId,
                searchQuery: _searchQuery,
                onAdd: _addToCart)),
      ]),
      bottomNavigationBar:
          cart.isEmpty ? null : _CartBar(onOpen: _openCartSheet),
    );
  }

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, sc) => CartPanel(
          onCheckout: () => _openPayment(closeCartSheet: true),
          scrollController: sc,
        ),
      ),
    );
  }

  void _openPayment({bool closeCartSheet = false}) {
    if (closeCartSheet) Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PaymentSheet(),
      );
    });
  }

  Future<void> _addToCart(Product product) async {
    HapticFeedback.lightImpact();
    final price = double.tryParse(product.price) ?? 0;
    final availableStock = double.tryParse(product.stock) ?? 0;
    final cart = ref.read(cartProvider);
    final quantityInCart = cart.items
        .where((item) => item.productId == product.id)
        .fold<double>(0, (sum, item) => sum + item.quantity);

    if (product.trackStock && quantityInCart >= availableStock) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          availableStock <= 0
              ? '${product.name} sedang habis.'
              : 'Stok ${product.name} hanya ${_formatStock(availableStock)}.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.danger,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    List<ProductVariant> storedVariants;
    try {
      storedVariants =
          await ref.read(databaseProvider).productDao.getVariants(product.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pilihan produk gagal dibaca. Coba lagi.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    if (!mounted) return;
    final variants = storedVariants
        .map((variant) => ProductVariantChoiceGroup(
              id: variant.id,
              name: variant.name.trim(),
              options: parseProductVariantOptionDetails(variant.options),
              isRequired: variant.isRequired,
            ))
        .where(
            (variant) => variant.name.isNotEmpty && variant.options.isNotEmpty)
        .toList();
    variants.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    String? variantSummary;
    var variantPriceDelta = 0.0;
    if (variants.isNotEmpty) {
      final selection =
          await showModalBottomSheet<ProductVariantSelectionResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ProductVariantSelectionSheet(
          productName: product.name,
          groups: variants,
        ),
      );
      if (!mounted || selection == null) return;
      variantSummary = selection.summary.isEmpty ? null : selection.summary;
      variantPriceDelta = selection.priceDelta;
    }

    Category? category;
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    for (final candidate in categories) {
      if (candidate.id == product.categoryId) {
        category = candidate;
        break;
      }
    }

    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: product.id,
          productName: product.name,
          unitPrice: price + variantPriceDelta,
          unitCogs: double.tryParse(product.cogs) ?? 0,
          variantSummary: variantSummary,
          trackStock: product.trackStock,
          availableStock: product.trackStock ? availableStock : null,
          categoryId: category?.id,
          categoryName: category?.name,
        ));
    HapticFeedback.selectionClick();
  }

  String _formatStock(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

// ── TOP BAR ───────────────────────────────────────────────────
class ProductVariantChoiceGroup {
  const ProductVariantChoiceGroup({
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

class ProductVariantSelectionResult {
  const ProductVariantSelectionResult({
    required this.summary,
    required this.priceDelta,
  });

  final String summary;
  final double priceDelta;
}

class ProductVariantSelectionSheet extends StatefulWidget {
  const ProductVariantSelectionSheet({
    super.key,
    required this.productName,
    required this.groups,
  });

  final String productName;
  final List<ProductVariantChoiceGroup> groups;

  @override
  State<ProductVariantSelectionSheet> createState() =>
      _ProductVariantSelectionSheetState();
}

class _ProductVariantSelectionSheetState
    extends State<ProductVariantSelectionSheet> {
  final Map<String, ProductVariantOption> _selected = {};
  String? _validationMessage;

  double get _selectedPriceDelta => totalVariantPriceDelta(_selected.values);

  void _submit() {
    final missing = widget.groups
        .where((group) => group.isRequired && !_selected.containsKey(group.id))
        .map((group) => group.name)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      setState(() {
        _validationMessage =
            'Pilih ${missing.join(', ')} sebelum menambah ke pesanan.';
      });
      return;
    }

    final summary = buildVariantSummary(widget.groups
        .where((group) => _selected[group.id]?.name.isNotEmpty == true)
        .map((group) => MapEntry(
              group.name,
              _cashierVariantOptionLabel(_selected[group.id]!),
            )));
    final priceDelta = totalVariantPriceDelta(_selected.values);
    Navigator.pop(
      context,
      ProductVariantSelectionResult(
        summary: summary,
        priceDelta: priceDelta,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + media.viewInsets.bottom,
        ),
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
              'Pilih untuk ${widget.productName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tambahan harga opsi dihitung otomatis ke item.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: widget.groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final group = widget.groups[index];
                  return Semantics(
                    container: true,
                    label:
                        '${group.name}, ${group.isRequired ? 'wajib' : 'opsional'}',
                    child: Container(
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
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: (group.isRequired
                                          ? AppTheme.primary
                                          : AppTheme.textSecondary)
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  group.isRequired ? 'Wajib' : 'Opsional',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: group.isRequired
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: group.options.map((option) {
                              final selected = _selected[group.id] == option;
                              return ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                child: ChoiceChip(
                                  label: Text(
                                    _cashierVariantOptionLabel(option),
                                  ),
                                  selected: selected,
                                  showCheckmark: true,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  onSelected: (_) {
                                    setState(() {
                                      if (selected && !group.isRequired) {
                                        _selected.remove(group.id);
                                      } else {
                                        _selected[group.id] = option;
                                      }
                                      _validationMessage = null;
                                    });
                                  },
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _validationMessage!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: Text(
                  _selectedPriceDelta > 0
                      ? 'Tambah (+${_selectedPriceDelta.toRupiah})'
                      : 'Tambah ke Pesanan',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cashierVariantOptionLabel(ProductVariantOption option) =>
    option.priceDelta > 0
        ? '${option.name} (+${option.priceDelta.toRupiah})'
        : option.name;

class _TopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final outlet = ref.watch(currentOutletProvider).value;
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDeep.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 12,
        16,
        12,
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const SajiaMark(
            size: 42,
            radius: 14,
            showBadge: false,
            backgroundColor: Colors.transparent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(AppBrand.name,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: AppTheme.textPrimary)),
            Text(
                '${outlet?.name.trim().isNotEmpty == true ? outlet!.name.trim() : 'Outlet aktif'} · ${DateHelper.formatDate(now)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        if (user != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openProfile(context, ref, user),
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }

  void _openProfile(BuildContext context, WidgetRef ref, AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.primaryLight,
                child: Text(
                  user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.roleLabel,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _confirmLogout(context, ref);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Keluar dari akun'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari Sajia?'),
        content: const Text('Sesi pengguna di perangkat ini akan diakhiri.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ref.read(cartProvider.notifier).clear();
    ref.read(currentUserProvider.notifier).state = null;
    context.go('/login');
  }
}

// ── CATEGORY BAR ──────────────────────────────────────────────
class _CategoryBar extends ConsumerWidget {
  final String? selected;
  final Function(String?) onSelect;

  const _CategoryBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(categoriesProvider);
    return SizedBox(
      height: 56,
      child: catsAsync.when(
        data: (cats) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          children: [
            _CatChip(
                label: 'Semua',
                selected: selected == null,
                onTap: () => onSelect(null)),
            ...cats.map((c) {
              Color color;
              try {
                color = Color(int.parse(c.colorHex.replaceFirst('#', '0xFF')));
              } catch (_) {
                color = AppTheme.primary;
              }
              return _CatChip(
                label: c.name,
                selected: selected == c.id,
                color: color,
                onTap: () => onSelect(c.id),
              );
            }),
          ],
        ),
        loading: () => const SizedBox(),
        error: (_, __) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(categoriesProvider),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Muat kategori'),
            style: TextButton.styleFrom(
              minimumSize: const Size(150, 48),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _CatChip(
      {required this.label,
      required this.selected,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c : AppTheme.subtleBorder),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : AppTheme.textSecondary,
            )),
      ),
    );
  }
}

// ── SEARCH BAR ────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Cari menu...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA9B3C2)),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 18, color: Color(0xFF9CA3AF)),
          suffixIcon: ctrl.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    ctrl.clear();
                    onChanged('');
                  },
                  child: const Icon(Icons.close,
                      size: 16, color: Color(0xFF9CA3AF)))
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.subtleBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.subtleBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5)),
        ),
      ),
    );
  }
}

// ── MENU GRID ─────────────────────────────────────────────────
class _MenuGrid extends ConsumerWidget {
  final String? categoryId;
  final String searchQuery;
  final Function(Product) onAdd;

  const _MenuGrid({
    required this.categoryId,
    required this.searchQuery,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(availableProductsProvider);
    final w = MediaQuery.of(context).size.width;
    final cols = w > 900
        ? 4
        : w > 600
            ? 3
            : 2;

    return productsAsync.when(
      data: (products) {
        final filtered = products.where((p) {
          final matchCat = categoryId == null || p.categoryId == categoryId;
          final matchSearch =
              searchQuery.isEmpty || p.name.toLowerCase().contains(searchQuery);
          return matchCat && matchSearch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fastfood_outlined, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                searchQuery.isNotEmpty
                    ? 'Menu tidak ditemukan'
                    : 'Belum ada menu',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ]),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 108),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: filtered.length,
          itemBuilder: (_, i) =>
              _MenuCard(product: filtered[i], onTap: () => onAdd(filtered[i])),
        );
      },
      loading: () => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => _SkeletonCard(),
      ),
      error: (_, __) => ErrorStateView(
        title: 'Menu belum bisa dimuat',
        onRetry: () => ref.invalidate(availableProductsProvider),
      ),
    );
  }
}

// ── MENU CARD ─────────────────────────────────────────────────
class _MenuCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;

  const _MenuCard({required this.product, required this.onTap});

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(widget.product.price) ?? 0;
    final stock = double.tryParse(widget.product.stock) ?? 0;
    final isOutOfStock = widget.product.trackStock && stock <= 0;

    return GestureDetector(
      onTap: isOutOfStock ? null : widget.onTap,
      onTapDown: isOutOfStock ? null : (_) => setState(() => _pressed = true),
      onTapCancel: isOutOfStock ? null : () => setState(() => _pressed = false),
      onTapUp: isOutOfStock ? null : (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isOutOfStock ? 0.68 : 1,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.subtleBorder, width: 0.7),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryDeep
                      .withValues(alpha: _pressed ? 0.04 : 0.08),
                  blurRadius: _pressed ? 10 : 20,
                  offset: Offset(0, _pressed ? 4 : 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProductImage(
                          source: widget.product.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          fallback: _imgPlaceholder(),
                        ),
                        if (widget.product.trackStock)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isOutOfStock
                                    ? AppTheme.danger
                                    : Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isOutOfStock
                                    ? 'Habis'
                                    : 'Stok ${_formatMenuStock(stock)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              isOutOfStock
                                  ? Icons.block_rounded
                                  : Icons.add_rounded,
                              color: isOutOfStock
                                  ? AppTheme.danger
                                  : AppTheme.primary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  price.toRupiah,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.touch_app_rounded,
                                color: Color(0xFFB9C4D2),
                                size: AppTheme.iconCompact,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatMenuStock(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Widget _imgPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryLight, AppTheme.goldLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
        ),
      );
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.subtleBorder, width: 0.5),
        ),
        child: Column(children: [
          Expanded(
              flex: 5,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
              )),
          Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 10,
                          width: 90,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(
                          height: 10,
                          width: 60,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(4))),
                    ]),
              )),
        ]),
      );
}

// ── CART BOTTOM BAR (HP) ──────────────────────────────────────
class _CartBar extends ConsumerWidget {
  final VoidCallback onOpen;
  const _CartBar({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final outlet = ref.watch(currentOutletProvider).value;
    final taxPercent = double.tryParse(outlet?.taxPercent ?? '0') ?? 0;
    final servicePercent =
        double.tryParse(outlet?.serviceChargePercent ?? '0') ?? 0;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.of(context).padding.bottom + 10,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.26),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${cart.itemCount} item',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          const Text('Lihat Pesanan',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(cart.total(taxPercent, servicePercent).toRupiah,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.keyboard_arrow_up,
              color: Colors.white,
              size: 18,
            ),
          ),
        ]),
      ),
    );
  }
}

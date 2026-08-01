import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/entities.dart';
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
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, sc) =>
            CartPanel(onCheckout: _openPayment, scrollController: sc),
      ),
    );
  }

  void _openPayment() {
    if (Navigator.canPop(context)) Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaymentSheet(),
    );
  }

  void _addToCart(Product product) {
    HapticFeedback.lightImpact();
    final price = double.tryParse(product.price) ?? 0;
    ref.read(cartProvider.notifier).addItem(CartItem(
          productId: product.id,
          productName: product.name,
          unitPrice: price,
        ));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text('+ ${product.name}'),
      ]),
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.success,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ── TOP BAR ───────────────────────────────────────────────────
class _TopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
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
            Text(DateHelper.formatDate(now),
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        if (user != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 12),
                ),
                const SizedBox(width: 6),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ]),
    );
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
      height: 46,
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
        error: (_, __) => const SizedBox(),
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
      error: (e, _) => Center(child: Text('Error: $e')),
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

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
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
                          child: const Icon(
                            Icons.add_rounded,
                            color: AppTheme.primary,
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
                              size: 15,
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
    );
  }

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

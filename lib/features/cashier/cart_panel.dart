import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/app_notice.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/entities/entities.dart';
import '../shared/polish_widgets.dart';

String _formatStock(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

class CartPanel extends ConsumerWidget {
  final VoidCallback onCheckout;
  final ScrollController? scrollController;

  const CartPanel({
    super.key,
    required this.onCheckout,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDeep.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Text('Pesanan',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                const SizedBox(width: 8),
                if (cart.itemCount > 0)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      key: ValueKey(cart.itemCount),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // Order type toggle
                _OrderTypeToggle(),
                if (cart.tableId != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_bar_outlined,
                            size: 14, color: Color(0xFF6B7280)),
                        const SizedBox(width: 4),
                        Text(cart.tableLabel ?? '-',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
                if (!cart.isEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _confirmClear(context, ref),
                    child: const Icon(Icons.delete_outline,
                        size: 20, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.subtleBorder),
          Expanded(
            child: cart.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: cart.items.length,
                    itemBuilder: (_, i) => _CartItemTile(
                      index: i,
                      item: cart.items[i],
                    ),
                  ),
          ),
          if (!cart.isEmpty) _buildSummary(context, ref, cart),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Belum ada pesanan',
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 4),
          Text('Tap menu untuk menambahkan',
              style: TextStyle(color: Colors.grey[300], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, WidgetRef ref, Cart cart) {
    final outlet = ref.watch(currentOutletProvider).value;
    final taxPercent = double.tryParse(outlet?.taxPercent ?? '0') ?? 0;
    final servicePercent =
        double.tryParse(outlet?.serviceChargePercent ?? '0') ?? 0;
    final total = cart.total(taxPercent, servicePercent);

    final bottomPadding = scrollController == null
        ? 16.0
        : bottomSheetSafePadding(context, extra: 0);

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDiscountSheet(context, ref, cart),
                  icon: Icon(
                    cart.discountValue > 0
                        ? Icons.sell_rounded
                        : Icons.percent_rounded,
                    size: 18,
                  ),
                  label: Text(
                    cart.discountValue > 0
                        ? 'Diskon ${_formatPercent(cart.discountPercent)}%'
                        : 'Atur diskon',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: cart.discountValue > 0
                        ? AppTheme.success
                        : AppTheme.primary,
                    side: BorderSide(
                      color: (cart.discountValue > 0
                              ? AppTheme.success
                              : AppTheme.primary)
                          .withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              if (cart.discountValue > 0) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () =>
                      ref.read(cartProvider.notifier).setDiscount(percent: 0),
                  tooltip: 'Hapus diskon',
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(46, 46),
                    foregroundColor: AppTheme.danger,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _SummaryRow('Subtotal', cart.subtotal.toRupiah),
          if (cart.discountValue > 0)
            _SummaryRow(
              'Diskon (${_formatPercent(cart.discountPercent)}%)',
              '-${cart.discountValue.toRupiah}',
              color: AppTheme.success,
            ),
          if (taxPercent > 0)
            _SummaryRow('Pajak (${taxPercent.toInt()}%)',
                cart.taxAmount(taxPercent).toRupiah),
          if (servicePercent > 0)
            _SummaryRow('Service (${servicePercent.toInt()}%)',
                cart.serviceChargeAmount(servicePercent).toRupiah),
          const Divider(height: 18, color: AppTheme.subtleBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(total.toRupiah,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppTheme.payGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onCheckout,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payment_rounded,
                          size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Bayar ${total.toRupiah}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiscountSheet(
    BuildContext context,
    WidgetRef ref,
    Cart cart,
  ) async {
    final result = await showModalBottomSheet<double>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DiscountSheet(initialPercent: cart.discountPercent),
    );
    if (result == null) return;
    ref.read(cartProvider.notifier).setDiscount(percent: result);
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pesanan?'),
        content: const Text('Semua item di keranjang akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(cartProvider.notifier).clear();
            },
            child:
                const Text('Hapus', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

String _formatPercent(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );
}

class _DiscountSheet extends StatefulWidget {
  final double initialPercent;

  const _DiscountSheet({required this.initialPercent});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialPercent > 0
          ? _formatPercent(widget.initialPercent)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectQuickValue(double value) {
    setState(() {
      _controller.text = _formatPercent(value);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _error = null;
    });
  }

  void _apply() {
    final normalized = _controller.text.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      setState(() => _error = 'Masukkan diskon dari 0 sampai 100%.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const quickValues = <double>[5, 10, 15, 20, 25, 50];
    final currentValue = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + keyboard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Atur Diskon',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Diskon berlaku untuk seluruh pesanan sebelum pajak dan service.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
              onChanged: (_) {
                setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Persentase diskon',
                hintText: 'Contoh: 10',
                suffixText: '%',
                errorText: _error,
                prefixIcon: const Icon(Icons.percent_rounded),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pilihan cepat',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickValues.map(
                (value) {
                  final selected = currentValue == value;
                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => _selectQuickValue(value),
                    label: Text('${_formatPercent(value)}%'),
                    avatar: Icon(
                      Icons.local_offer_outlined,
                      size: 16,
                      color: selected ? Colors.white : AppTheme.primary,
                    ),
                    backgroundColor: Colors.white,
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppTheme.primaryDeep,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.primary.withValues(alpha: 0.28),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                  );
                },
              ).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Terapkan Diskon'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            if (widget.initialPercent > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(0.0),
                  child: const Text('Hapus diskon'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── CART ITEM TILE ─────────────────────────────────────────────
class _CartItemTile extends ConsumerWidget {
  final int index;
  final CartItem item;

  const _CartItemTile({required this.index, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: Row(
          children: [
            Row(
              children: [
                _QtyButton(
                  icon: Icons.remove,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(cartProvider.notifier).decrementQty(index);
                  },
                ),
                SizedBox(
                  width: 30,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(
                      item.quantity.toInt().toString(),
                      key: ValueKey(item.quantity),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                _QtyButton(
                  icon: Icons.add,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (item.trackStock &&
                        item.availableStock != null &&
                        item.quantity >= item.availableStock!) {
                      AppNotice.show(context, SnackBar(
                        content: Text(
                          'Stok ${item.productName} hanya ${_formatStock(item.availableStock!)}.',
                        ),
                        backgroundColor: AppTheme.danger,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    ref.read(cartProvider.notifier).incrementQty(index);
                  },
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  if (item.variantSummary != null)
                    Text(item.variantSummary!,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  if (item.notes != null)
                    Text('Catatan: ${item.notes}',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  if (item.trackStock && item.availableStock != null)
                    Text(
                      'Stok tersedia: ${_formatStock(item.availableStock!)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.subtotal.toRupiah,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  State<_QtyButton> createState() => _QtyButtonState();
}

class _QtyButtonState extends State<_QtyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(widget.icon, size: 20, color: AppTheme.primary),
        ),
      ),
    );
  }
}

// ── ORDER TYPE TOGGLE ──────────────────────────────────────────
class _OrderTypeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final tablesAsync = ref.watch(tablesProvider);

    final hasTables = tablesAsync.maybeWhen(
      data: (tables) => tables.isNotEmpty,
      orElse: () => false,
    );

    final types = [
      ('dine_in', Icons.table_restaurant_outlined, 'Dine In'),
      ('takeaway', Icons.takeout_dining_outlined, 'Take Away'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: types.map((t) {
        final selected = cart.orderType == t.$1;
        return GestureDetector(
          onTap: () {
            if (t.$1 == 'dine_in' && hasTables) {
              // Ada meja → buka sheet pilih meja
              _showTablePicker(context, ref);
            } else {
              // Tidak ada meja ATAU pilih takeaway → langsung set, clear meja
              ref.read(cartProvider.notifier).setOrderType(t.$1);
              ref.read(cartProvider.notifier).setTable(null, null);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.subtleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.$2,
                    size: 14,
                    color:
                        selected ? AppTheme.primary : AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  t.$3,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showTablePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TablePickerSheet(ref: ref),
    );
  }
}

// ── TABLE PICKER SHEET ────────────────────────────────────────
class _TablePickerSheet extends ConsumerWidget {
  final WidgetRef ref;
  const _TablePickerSheet({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final tablesAsync = widgetRef.watch(tablesProvider);
    final cart = widgetRef.watch(cartProvider);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Pilih Meja',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Tap meja untuk dine in',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            Flexible(
              child: tablesAsync.when(
                data: (tables) => GridView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (_, i) {
                    final table = tables[i];
                    final isSelected = cart.tableId == table.id;
                    // Asumsi model Table punya field: id, name/label, isOccupied
                    final isOccupied = table.status == 'occupied';

                    return GestureDetector(
                      onTap: isOccupied
                          ? null
                          : () {
                              widgetRef.read(cartProvider.notifier)
                                ..setOrderType('dine_in')
                                ..setTable(table.id, table.tableLabel);
                              Navigator.pop(context);
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryLight
                              : isOccupied
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primary
                                : isOccupied
                                    ? AppTheme.danger
                                    : AppTheme.borderColor,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.table_bar_rounded,
                              size: 22,
                              color: isSelected
                                  ? AppTheme.primary
                                  : isOccupied
                                      ? AppTheme.danger
                                      : const Color(0xFF6B7280),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              table.tableLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? AppTheme.primary
                                    : isOccupied
                                        ? AppTheme.danger
                                        : const Color(0xFF374151),
                              ),
                            ),
                            if (isOccupied)
                              const Text('Terpakai',
                                  style: TextStyle(
                                      fontSize: 9, color: AppTheme.danger)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                loading: () => const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )),
                error: (_, __) => ErrorStateView(
                  title: 'Daftar meja belum bisa dimuat',
                  onRetry: () => widgetRef.invalidate(tablesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SUMMARY ROW ───────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color ?? const Color(0xFF374151),
              )),
        ],
      ),
    );
  }
}

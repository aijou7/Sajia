import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/entities/entities.dart';

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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: cart.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      key: ValueKey(cart.items.length),
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: cart.items.length,
                      itemBuilder: (_, i) => _CartItemTile(
                        index: i,
                        item: cart.items[i],
                      ),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        children: [
          _SummaryRow('Subtotal', cart.subtotal.toRupiah),
          if (cart.discountValue > 0)
            _SummaryRow('Diskon', '-${cart.discountValue.toRupiah}',
                color: AppTheme.success),
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
                    ref
                        .read(cartProvider.notifier)
                        .updateQty(index, item.quantity - 1);
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
                    ref
                        .read(cartProvider.notifier)
                        .updateQty(index, item.quantity + 1);
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(widget.icon, size: 15, color: AppTheme.primary),
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

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
          tablesAsync.when(
            data: (tables) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ],
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

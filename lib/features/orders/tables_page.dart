import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/numeric_input_formatter.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../shared/polish_widgets.dart';

String _tablePercentLabel(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class TablesPage extends ConsumerWidget {
  const TablesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesProvider);
    final activeOrdersAsync = ref.watch(activeOrdersProvider);
    final canManageTables =
        ref.watch(currentUserProvider)?.canManageOperations == true;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Meja'),
        actions: canManageTables
            ? [
                TextButton.icon(
                  onPressed: () => _openAddTable(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppTheme.primary),
                ),
              ]
            : null,
      ),
      body: tablesAsync.when(
        data: (tables) {
          if (tables.isEmpty) {
            return EmptyStateView(
              icon: Icons.table_bar_outlined,
              title: 'Belum ada meja',
              subtitle: canManageTables
                  ? 'Tambah meja untuk mulai terima pesanan dine in.'
                  : 'Meja belum disiapkan oleh owner atau manager.',
              action: canManageTables
                  ? ElevatedButton.icon(
                      onPressed: () => _openAddTable(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Meja'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.action,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  : null,
            );
          }

          // Group by area
          final areas = <String>{};
          for (final t in tables) {
            areas.add(t.area ?? 'Umum');
          }

          return activeOrdersAsync.when(
            data: (orders) {
              final orderByTable = <String, Order>{};
              for (final o in orders) {
                if (o.tableId != null) orderByTable[o.tableId!] = o;
              }

              return ListView(
                padding: const EdgeInsets.only(bottom: 18),
                children: [
                  ModernHeroHeader(
                    title: '${tables.length} Meja',
                    subtitle: canManageTables
                        ? '${orders.length} order aktif. Tap meja tersedia untuk dipakai, tombol edit untuk ubah.'
                        : '${orders.length} order aktif. Tap meja tersedia untuk dipakai.',
                    icon: Icons.table_restaurant_rounded,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Live',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  ...areas.map((area) {
                    final areaT = tables
                        .where((t) => (t.area ?? 'Umum') == area)
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(area.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF9CA3AF))),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 600 ? 4 : 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio:
                                MediaQuery.of(context).size.width > 600
                                    ? 1.05
                                    : 0.78,
                          ),
                          itemCount: areaT.length,
                          itemBuilder: (_, i) => _TableCard(
                            table: areaT[i],
                            activeOrder: orderByTable[areaT[i].id],
                            canManage: canManageTables,
                            onTap: () => _onTableTap(context, ref, areaT[i],
                                orderByTable[areaT[i].id]),
                            onLongPress: canManageTables
                                ? () => _openEditTable(context, ref, areaT[i])
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => ErrorStateView(
              title: 'Status meja belum bisa dimuat',
              subtitle:
                  'Daftar meja aman. Muat ulang untuk mengecek order aktif.',
              onRetry: () => ref.invalidate(activeOrdersProvider),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErrorStateView(
          title: 'Daftar meja belum bisa dimuat',
          subtitle: 'Coba muat ulang data meja outlet ini.',
          onRetry: () => ref.invalidate(tablesProvider),
        ),
      ),
    );
  }

  void _onTableTap(BuildContext ctx, WidgetRef ref, RestaurantTable table,
      Order? activeOrder) {
    if (table.status == 'occupied' && activeOrder != null) {
      // Tampilkan detail order aktif
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ActiveOrderSheet(table: table, order: activeOrder),
      );
    } else if (table.status == 'available') {
      // Set meja ke cart — TANPA Navigator.pop, user tetap di halaman meja
      ref.read(cartProvider.notifier)
        ..setOrderType('dine_in')
        ..setTable(table.id, table.tableLabel);

      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Meja ${table.tableLabel} dipilih'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }

  void _openAddTable(BuildContext ctx, WidgetRef ref) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TableFormSheet(),
    );
  }

  void _openEditTable(BuildContext ctx, WidgetRef ref, RestaurantTable table) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TableFormSheet(table: table),
    );
  }
}

// ── TABLE CARD ────────────────────────────────────────────────
class _TableCard extends StatelessWidget {
  final RestaurantTable table;
  final Order? activeOrder;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TableCard({
    required this.table,
    this.activeOrder,
    required this.canManage,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = table.status == 'occupied';

    Color bgColor = Colors.white;
    Color borderColor = AppTheme.borderColor;
    Color statusColor = AppTheme.tableAvailable;
    String statusLabel = 'Tersedia';

    if (isOccupied) {
      bgColor = const Color(0xFFFFF1F2);
      borderColor = AppTheme.tableOccupied.withValues(alpha: 0.3);
      statusColor = AppTheme.tableOccupied;
      statusLabel = 'Terisi';
    } else if (table.status == 'cleaning') {
      bgColor = const Color(0xFFF9FAFB);
      borderColor = AppTheme.borderColor;
      statusColor = AppTheme.tableCleaning;
      statusLabel = 'Dibersihkan';
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: isOccupied ? 0.12 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          children: [
            // Baris atas — tombol edit
            if (canManage)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    tooltip: 'Edit ${table.tableLabel}',
                    onPressed: onLongPress,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.84),
                      side: const BorderSide(color: AppTheme.subtleBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 28),

            // Konten tengah
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isOccupied
                          ? Icons.people_rounded
                          : Icons.table_restaurant_outlined,
                      color: statusColor,
                      size: AppTheme.iconProminent,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      table.tableLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (isOccupied && activeOrder != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      activeOrder!.total.isNotEmpty
                          ? 'Rp ${_formatAmount(activeOrder!.total)}'
                          : '',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatAmount(String amount) {
    final val = double.tryParse(amount) ?? 0;
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}jt';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}rb';
    return val.toStringAsFixed(0);
  }
}

// ── ACTIVE ORDER SHEET ────────────────────────────────────────
class _ActiveOrderSheet extends ConsumerWidget {
  final RestaurantTable table;
  final Order order;

  const _ActiveOrderSheet({required this.table, required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(orderItemsProvider(order.id));
    final canCorrectOrders =
        ref.watch(currentUserProvider)?.canManageOperations == true;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        bottomSheetSafePadding(context),
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
            )),
            Row(
              children: [
                Text(table.tableLabel,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.tableOccupied.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(order.orderNumber,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.tableOccupied,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Items
            itemsAsync.when(
              data: (items) => Column(
                children: items
                    .map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text('${item.quantity}x ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary)),
                              Expanded(
                                  child: Text(item.productName,
                                      style: const TextStyle(fontSize: 13))),
                              Text('Rp ${item.subtotal}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(orderItemsProvider(order.id)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Muat ulang detail item'),
                ),
              ),
            ),

            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                Text((double.tryParse(order.subtotal) ?? 0).toRupiah,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            if ((double.tryParse(order.discountAmount) ?? 0) > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Diskon (${_tablePercentLabel(double.tryParse(order.discountPercent) ?? 0)}%)',
                    style:
                        const TextStyle(fontSize: 13, color: AppTheme.success),
                  ),
                  Text(
                    '-${(double.tryParse(order.discountAmount) ?? 0).toRupiah}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Rp ${order.total}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary)),
              ],
            ),
            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                if (canCorrectOrders) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Set meja ke cart untuk edit order
                        ref
                            .read(cartProvider.notifier)
                            .setTable(table.id, table.tableLabel);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit Order'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final navigatorContext =
                          Navigator.of(context, rootNavigator: true).context;
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!navigatorContext.mounted) return;
                        showModalBottomSheet(
                          context: navigatorContext,
                          isScrollControlled: true,
                          useSafeArea: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              _OrderPaymentSheet(table: table, order: order),
                        );
                      });
                    },
                    icon: const Icon(Icons.payment_rounded, size: 16),
                    label: const Text('Bayar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPaymentSheet extends ConsumerStatefulWidget {
  final RestaurantTable table;
  final Order order;

  const _OrderPaymentSheet({
    required this.table,
    required this.order,
  });

  @override
  ConsumerState<_OrderPaymentSheet> createState() => _OrderPaymentSheetState();
}

class _OrderPaymentSheetState extends ConsumerState<_OrderPaymentSheet> {
  final _paidCtrl = TextEditingController();
  String _method = 'cash';
  bool _isSaving = false;

  double get _total => double.tryParse(widget.order.total) ?? 0;
  double get _paidAmount =>
      _method == 'cash' ? (double.tryParse(_paidCtrl.text) ?? 0) : _total;
  double get _change => (_paidAmount - _total).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _paidCtrl.text = _total.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_method == 'cash' && _paidAmount < _total) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Uang bayar kurang'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    setState(() => _isSaving = true);

    await ref.read(databaseProvider).orderDao.completePayment(
          orderId: widget.order.id,
          paymentMethod: _method,
          paidAmount: _paidAmount,
          changeAmount: _method == 'cash' ? _change : 0,
          tableId: widget.table.id,
        );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Order ${widget.order.orderNumber} sudah dibayar'),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
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
        left: 20,
        right: 20,
        top: 12,
        bottom: bottomSheetSafePadding(context),
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
            Text(
              'Bayar ${widget.table.tableLabel}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(widget.order.orderNumber,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  _total.toRupiah,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PaymentChoice(
                    label: 'Tunai',
                    icon: Icons.payments_outlined,
                    selected: _method == 'cash',
                    onTap: () => setState(() => _method = 'cash'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PaymentChoice(
                    label: 'QRIS',
                    icon: Icons.qr_code_rounded,
                    selected: _method == 'qris',
                    onTap: () => setState(() => _method = 'qris'),
                  ),
                ),
              ],
            ),
            if (_method == 'cash') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _paidCtrl,
                selectAllOnFocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: const [NormalizedNumberInputFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Uang diterima',
                  prefixText: 'Rp ',
                  hintText: '0',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Kembalian: ${_change.toRupiah}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline),
                label:
                    Text(_isSaving ? 'Memproses...' : 'Selesaikan Pembayaran'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLight : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? AppTheme.primary : const Color(0xFF6B7280)),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTheme.primary : const Color(0xFF374151),
                )),
          ],
        ),
      ),
    );
  }
}

// ── TABLE FORM SHEET ──────────────────────────────────────────
class _TableFormSheet extends ConsumerStatefulWidget {
  final RestaurantTable? table;
  const _TableFormSheet({this.table});

  @override
  ConsumerState<_TableFormSheet> createState() => _TableFormSheetState();
}

class _TableFormSheetState extends ConsumerState<_TableFormSheet> {
  final _labelCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  int _capacity = 4;
  bool _isSaving = false;

  bool get _isEdit => widget.table != null;

  @override
  void initState() {
    super.initState();
    _labelCtrl.text = widget.table?.tableLabel ?? '';
    _areaCtrl.text = widget.table?.area ?? '';
    _capacity = widget.table?.capacity ?? 4;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (ref.read(currentUserProvider)?.canManageOperations != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kasir tidak memiliki akses mengubah meja.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    if (_labelCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final id = widget.table?.id ?? const Uuid().v4();

    await db.orderDao.upsertTable(RestaurantTablesCompanion(
      id: Value(id),
      outletId: Value(outletId),
      tableLabel: Value(_labelCtrl.text.trim()),
      area: Value(_areaCtrl.text.trim().isEmpty ? null : _areaCtrl.text.trim()),
      capacity: Value(_capacity),
      updatedAt: Value(DateTime.now()),
      isSynced: const Value(false),
    ));

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (ref.read(currentUserProvider)?.canManageOperations != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kasir tidak memiliki akses menghapus meja.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus meja?'),
        content: Text('Meja "${widget.table!.tableLabel}" akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Hapus', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isSaving = true);
      final db = ref.read(databaseProvider);
      await db.orderDao.deleteTable(widget.table!.id); // ← ini yang ditambah
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
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
            Row(
              children: [
                Text(_isEdit ? 'Edit Meja' : 'Tambah Meja',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_isEdit)
                  TextButton(
                    onPressed: _delete,
                    child: const Text('Hapus',
                        style: TextStyle(color: AppTheme.danger)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Nama Meja *',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            TextField(
              controller: _labelCtrl,
              decoration: InputDecoration(
                hintText: 'Contoh: Meja 1, VIP A, Bar 2',
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
            const SizedBox(height: 14),
            const Text('Area (opsional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            TextField(
              controller: _areaCtrl,
              decoration: InputDecoration(
                hintText: 'Contoh: Indoor, Outdoor, Rooftop',
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
            const SizedBox(height: 14),
            const Text('Kapasitas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_capacity > 1) setState(() => _capacity--);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.remove, size: 18),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text('$_capacity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _capacity++),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Text('orang',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ],
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
                    : Text(_isEdit ? 'Simpan' : 'Tambah Meja',
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

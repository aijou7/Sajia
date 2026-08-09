import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/brand.dart';
import '../../core/print_service.dart';
import '../../data/local/app_database.dart';
import '../shared/polish_widgets.dart';

class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  DateTime _selectedDate = DateTime.now();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(DateTime.now())
          ? DateTime.now()
          : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal transaksi',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final outletId = ref.watch(currentOutletIdProvider);

    final from = DateHelper.startOfDay(_selectedDate);
    final to = DateHelper.endOfDay(_selectedDate);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
      ),
      body: Column(
        children: [
          // Date navigator
          ModernCard(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left_rounded),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickDate,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pilih tanggal',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_month_outlined, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                DateHelper.formatDate(_selectedDate),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final next = _selectedDate.add(const Duration(days: 1));
                    if (next.isBefore(
                        DateTime.now().add(const Duration(days: 1)))) {
                      setState(() => _selectedDate = next);
                    }
                  },
                  icon: const Icon(Icons.chevron_right_rounded),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ],
            ),
          ),

          // Order list
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: _watchOrders(db, outletId, from, to),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(
                    child: EmptyStateView(
                      icon: Icons.cloud_off_outlined,
                      title: 'Riwayat belum bisa dimuat',
                      subtitle:
                          'Periksa data outlet lalu buka kembali halaman ini.',
                    ),
                  );
                }

                final orders = snapshot.data!;
                final paid = orders.where((o) => o.status == 'paid').toList();
                final voided = orders.where((o) => o.status == 'void').toList();

                // Summary bar
                final totalRevenue = paid.fold(
                    0.0, (sum, o) => sum + (double.tryParse(o.total) ?? 0));

                return Column(
                  children: [
                    // Summary bar
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.floatingShadow,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryItem(
                              label: 'Total Transaksi',
                              value: '${paid.length}',
                              icon: Icons.receipt_long_outlined,
                            ),
                          ),
                          Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withValues(alpha: 0.2)),
                          Expanded(
                            child: _SummaryItem(
                              label: 'Total Omzet',
                              value: totalRevenue.toRupiahCompact,
                              icon: Icons.trending_up_rounded,
                            ),
                          ),
                          if (voided.isNotEmpty) ...[
                            Container(
                                width: 1,
                                height: 36,
                                color: Colors.white.withValues(alpha: 0.2)),
                            Expanded(
                              child: _SummaryItem(
                                label: 'Void',
                                value: '${voided.length}',
                                icon: Icons.cancel_outlined,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // List
                    Expanded(
                      child: orders.isEmpty
                          ? const Center(
                              child: EmptyStateView(
                                icon: Icons.receipt_long_outlined,
                                title: 'Belum ada transaksi',
                                subtitle:
                                    'Transaksi yang sudah dibayar akan muncul di sini.',
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: orders.length,
                              itemBuilder: (_, i) => _OrderTile(
                                order: orders[i],
                                onChanged: () => setState(() {}),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<List<Order>> _watchOrders(
    AppDatabase db,
    String outletId,
    DateTime from,
    DateTime to,
  ) =>
      (db.select(db.orders)
            ..where((order) =>
                order.outletId.equals(outletId) &
                order.createdAt.isBetweenValues(from, to))
            ..orderBy([(order) => OrderingTerm.desc(order.createdAt)]))
          .watch();
}

// ── ORDER TILE ────────────────────────────────────────────────
class _OrderTile extends ConsumerWidget {
  final Order order;
  final VoidCallback onChanged;

  const _OrderTile({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = order.status == 'paid';
    final isVoid = order.status == 'void';
    final total = double.tryParse(order.total) ?? 0;
    final change = double.tryParse(order.changeAmount ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isVoid
              ? AppTheme.danger.withValues(alpha: 0.2)
              : AppTheme.subtleBorder,
        ),
        boxShadow: AppTheme.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPaid
                  ? AppTheme.success.withValues(alpha: 0.1)
                  : AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPaid ? Icons.check_rounded : Icons.close_rounded,
              color: isPaid ? AppTheme.success : AppTheme.danger,
              size: 18,
            ),
          ),
          title: Row(
            children: [
              Text(order.orderNumber,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              if (order.tableLabel != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(order.tableLabel!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${DateHelper.formatTime(order.createdAt)} · ${order.cashierName}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total.toRupiah,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPaid ? AppTheme.primary : AppTheme.danger,
                  decoration: isVoid ? TextDecoration.lineThrough : null,
                ),
              ),
              if (isVoid)
                const Text('VOID',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          children: [
            // Detail order
            _OrderDetail(order: order, change: change, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// ── ORDER DETAIL ──────────────────────────────────────────────
class _OrderDetail extends ConsumerWidget {
  final Order order;
  final double change;
  final VoidCallback onChanged;

  const _OrderDetail({
    required this.order,
    required this.change,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(orderItemsProvider(order.id));
    final total = double.tryParse(order.total) ?? 0;
    final paid = double.tryParse(order.paidAmount ?? '0') ?? 0;
    final user = ref.watch(currentUserProvider);
    final canCorrectOrder = user?.canVoidTransactions == true;

    return itemsAsync.when(
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Items
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('${item.quantity}x ',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                    Expanded(
                      child: Text(item.productName,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text(item.subtotal,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Payment info
          _DetailRow('Total', total.toRupiah, bold: true),
          _DetailRow('Bayar (${order.paymentMethod?.toUpperCase() ?? '-'})',
              paid.toRupiah),
          if (change > 0)
            _DetailRow('Kembali', change.toRupiah, color: AppTheme.warning),
          if (order.voidReason != null) ...[
            const SizedBox(height: 4),
            _DetailRow('Alasan void', order.voidReason!,
                color: AppTheme.danger),
          ],
          if (order.status == 'paid') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _printReceipt(context, ref, items),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Cetak ulang struk'),
              ),
            ),
          ],
          if (canCorrectOrder && order.status != 'void') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmVoid(context, ref),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Void / batalkan transaksi'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side:
                      BorderSide(color: AppTheme.danger.withValues(alpha: .4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      loading: () => const Center(
          child: Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => Center(
        child: TextButton.icon(
          onPressed: () => ref.invalidate(orderItemsProvider(order.id)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Muat ulang detail item'),
        ),
      ),
    );
  }

  Future<void> _printReceipt(
    BuildContext context,
    WidgetRef ref,
    List<OrderItem> items,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Mengirim struk ke printer...')),
          ],
        ),
      ),
    );

    PrintResult result;
    try {
      final db = ref.read(databaseProvider);
      final outlet = await (db.select(db.outlets)
            ..where((row) => row.id.equals(order.outletId)))
          .getSingleOrNull();
      final receipt = ReceiptData(
        outletName: outlet?.name ?? AppBrand.name,
        outletAddress: outlet?.address,
        outletPhone: outlet?.phone,
        receiptHeader: outlet?.receiptHeader,
        receiptFooter: outlet?.receiptFooter,
        orderNumber: order.orderNumber,
        tableLabel: order.tableLabel,
        cashierName: order.cashierName,
        paymentMethod: order.paymentMethod ?? '-',
        items: items
            .map((item) => ReceiptItem(
                  name: item.productName,
                  variantSummary: item.variantSummary,
                  quantity: double.tryParse(item.quantity) ?? 0,
                  unitPrice: double.tryParse(item.unitPrice) ?? 0,
                  subtotal: double.tryParse(item.subtotal) ?? 0,
                ))
            .toList(),
        subtotal: double.tryParse(order.subtotal) ?? 0,
        discountAmount: double.tryParse(order.discountAmount) ?? 0,
        taxAmount: double.tryParse(order.taxAmount) ?? 0,
        serviceCharge: double.tryParse(order.serviceCharge) ?? 0,
        total: double.tryParse(order.total) ?? 0,
        paidAmount: double.tryParse(order.paidAmount ?? '0') ?? 0,
        changeAmount: double.tryParse(order.changeAmount ?? '0') ?? 0,
        paidAt: order.paidAt ?? order.createdAt,
      );
      result = await PrintService().printReceipt(receipt);
    } catch (_) {
      result = PrintResult.error;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? AppTheme.success : AppTheme.danger,
      ),
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Transaksi ${order.orderNumber} akan dibatalkan dari laporan.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Alasan',
                hintText: 'Contoh: salah input pembayaran',
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Void'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;
    if (!context.mounted) return;

    final user = ref.read(currentUserProvider);
    if (user?.canVoidTransactions != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kasir tidak memiliki akses membatalkan transaksi.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    await ref.read(databaseProvider).orderDao.voidOrder(
          order.id,
          reason.isEmpty ? 'Koreksi transaksi' : reason,
          user!.name,
        );
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transaksi berhasil di-void.'),
        backgroundColor: AppTheme.success,
      ));
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _DetailRow(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          Text(value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: color ?? const Color(0xFF374151),
              )),
        ],
      ),
    );
  }
}

// ── SUMMARY ITEM ──────────────────────────────────────────────
class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }
}

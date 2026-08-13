import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/numeric_input_formatter.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/entities.dart';

class ShiftPage extends ConsumerStatefulWidget {
  const ShiftPage({super.key});

  @override
  ConsumerState<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends ConsumerState<ShiftPage> {
  Session? _session;
  _ShiftTotals _totals = const _ShiftTotals();
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    final outletId = ref.read(currentOutletIdProvider);
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Pengguna aktif tidak ditemukan. Masuk ulang dengan PIN.';
        });
      }
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final session = await (db.select(db.sessions)
            ..where(
              (row) =>
                  row.outletId.equals(outletId) &
                  row.cashierId.equals(user.id) &
                  row.closedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.openedAt)])
            ..limit(1))
          .getSingleOrNull();
      final totals = session == null
          ? const _ShiftTotals()
          : await _calculateTotals(db, outletId, user.id, session.openedAt);

      if (!mounted) return;
      setState(() {
        _session = session;
        _totals = totals;
        _loading = false;
        _error = null;
      });
      ref.read(activeShiftProvider.notifier).state = session == null
          ? null
          : SessionData(
              id: session.id,
              cashierId: session.cashierId,
              cashierName: session.cashierName,
              openingCash: _money(session.openingCash),
              openedAt: session.openedAt,
            );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Shift belum dapat dimuat. Tarik ke bawah untuk mencoba lagi.';
      });
      debugPrint('[ShiftPage] load failed: $error');
    }
  }

  Future<_ShiftTotals> _calculateTotals(
    AppDatabase db,
    String outletId,
    String cashierId,
    DateTime openedAt,
  ) async {
    final orders = await (db.select(db.orders)
          ..where(
            (row) =>
                row.outletId.equals(outletId) &
                row.cashierId.equals(cashierId) &
                row.updatedAt.isBiggerOrEqualValue(openedAt),
          ))
        .get();

    var cash = 0.0;
    var qris = 0.0;
    var other = 0.0;
    var voidAmount = 0.0;
    var paidOrders = 0;
    var voidOrders = 0;
    for (final order in orders) {
      final total = _money(order.total);
      final paidDuringShift = order.paidAt != null &&
          !order.paidAt!.isBefore(openedAt) &&
          order.status == 'paid';
      if (paidDuringShift) {
        paidOrders += 1;
        switch (order.paymentMethod?.toLowerCase()) {
          case 'cash':
            cash += total;
            break;
          case 'qris':
            qris += total;
            break;
          default:
            other += total;
            break;
        }
      } else if (order.status == 'void' &&
          !order.updatedAt.isBefore(openedAt)) {
        voidOrders += 1;
        voidAmount += total;
      }
    }
    return _ShiftTotals(
      cashSales: cash,
      qrisSales: qris,
      otherSales: other,
      voidAmount: voidAmount,
      paidOrders: paidOrders,
      voidOrders: voidOrders,
    );
  }

  Future<void> _openShift() async {
    final openingCash = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _OpeningCashSheet(),
    );
    if (openingCash == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buka shift kasir?'),
        content: Text(
          'Modal awal tercatat ${openingCash.toRupiah}. Pastikan uang fisik di laci sudah sesuai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Periksa lagi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buka shift'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final user = ref.read(currentUserProvider);
    final outletId = ref.read(currentOutletIdProvider);
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      final db = ref.read(databaseProvider);
      final existing = await (db.select(db.sessions)
            ..where(
              (row) =>
                  row.outletId.equals(outletId) &
                  row.cashierId.equals(user.id) &
                  row.closedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();
      if (existing == null) {
        final now = DateTime.now();
        await db.sessionDao.openSession(
          SessionsCompanion.insert(
            id: const Uuid().v4(),
            outletId: outletId,
            cashierId: user.id,
            cashierName: user.name,
            openingCash: Value(openingCash.toStringAsFixed(0)),
            openedAt: Value(now),
          ),
        );
      }
      await _load();
      unawaited(ref.read(syncServiceProvider).syncAll());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift kasir berhasil dibuka.')),
        );
      }
    } catch (error) {
      debugPrint('[ShiftPage] open failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift gagal dibuka. Coba lagi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _closeShift() async {
    final session = _session;
    if (session == null) return;
    final expectedCash = _money(session.openingCash) + _totals.cashSales;
    final input = await showModalBottomSheet<_CloseShiftInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CloseShiftSheet(expectedCash: expectedCash),
    );
    if (input == null || !mounted) return;

    final discrepancy = input.actualCash - expectedCash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tutup shift kasir?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogLine(label: 'Kas seharusnya', value: expectedCash.toRupiah),
            _DialogLine(label: 'Kas aktual', value: input.actualCash.toRupiah),
            _DialogLine(
              label: 'Selisih',
              value: _signedMoney(discrepancy),
              color:
                  discrepancy.abs() < 0.5 ? AppTheme.success : AppTheme.danger,
            ),
            const SizedBox(height: 12),
            const Text(
              'Setelah ditutup, transaksi berikutnya tidak termasuk shift ini.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tutup shift'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final db = ref.read(databaseProvider);
      await db.sessionDao.closeSession(
        sessionId: session.id,
        closingCash: input.actualCash,
        totalCashSales: _totals.cashSales,
        totalQrisSales: _totals.qrisSales,
        totalOrders: _totals.paidOrders,
        totalVoids: _totals.voidOrders,
        notes: input.notes,
      );
      ref.read(activeShiftProvider.notifier).state = null;
      unawaited(ref.read(syncServiceProvider).syncAll());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              discrepancy.abs() < 0.5
                  ? 'Shift ditutup. Kas sesuai.'
                  : 'Shift ditutup dengan selisih ${_signedMoney(discrepancy)}.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('[ShiftPage] close failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift gagal ditutup. Coba lagi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Shift Kasir')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + bottomInset),
            children: [
              if (_loading)
                const SizedBox(
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorState(message: _error!, onRetry: _load)
              else if (_session == null)
                _EmptyShiftState(
                  submitting: _submitting,
                  onOpen: _openShift,
                )
              else ...[
                _ActiveShiftHero(session: _session!),
                const SizedBox(height: 18),
                _ShiftMetrics(totals: _totals),
                const SizedBox(height: 18),
                _CashReconciliation(
                  openingCash: _money(_session!.openingCash),
                  cashSales: _totals.cashSales,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _closeShift,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_clock_rounded),
                    label: const Text('Tutup shift & rekonsiliasi'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftTotals {
  final double cashSales;
  final double qrisSales;
  final double otherSales;
  final double voidAmount;
  final int paidOrders;
  final int voidOrders;

  const _ShiftTotals({
    this.cashSales = 0,
    this.qrisSales = 0,
    this.otherSales = 0,
    this.voidAmount = 0,
    this.paidOrders = 0,
    this.voidOrders = 0,
  });

  double get totalSales => cashSales + qrisSales + otherSales;
}

class _ActiveShiftHero extends StatelessWidget {
  final Session session;
  const _ActiveShiftHero({required this.session});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.floatingShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHIFT AKTIF',
                        style: TextStyle(
                          color: AppTheme.accentLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.cashierName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Berjalan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Dibuka ${DateHelper.formatDateTime(session.openedAt)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class _ShiftMetrics extends StatelessWidget {
  final _ShiftTotals totals;
  const _ShiftMetrics({required this.totals});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                width: cardWidth,
                icon: Icons.payments_rounded,
                label: 'Penjualan tunai',
                value: totals.cashSales.toRupiahCompact,
                color: AppTheme.success,
              ),
              _MetricCard(
                width: cardWidth,
                icon: Icons.qr_code_2_rounded,
                label: 'Penjualan QRIS',
                value: totals.qrisSales.toRupiahCompact,
                color: AppTheme.primary,
              ),
              _MetricCard(
                width: cardWidth,
                icon: Icons.receipt_long_rounded,
                label: 'Transaksi dibayar',
                value: '${totals.paidOrders}',
                detail: totals.totalSales.toRupiahCompact,
                color: AppTheme.info,
              ),
              _MetricCard(
                width: cardWidth,
                icon: Icons.assignment_return_rounded,
                label: 'Transaksi void',
                value: '${totals.voidOrders}',
                detail: totals.voidAmount.toRupiahCompact,
                color: AppTheme.danger,
              ),
            ],
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color color;

  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 124),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 13),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail!,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
}

class _CashReconciliation extends StatelessWidget {
  final double openingCash;
  final double cashSales;
  const _CashReconciliation({
    required this.openingCash,
    required this.cashSales,
  });

  @override
  Widget build(BuildContext context) {
    final expected = openingCash + cashSales;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.subtleBorder),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: AppTheme.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kas di laci',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MoneyLine(label: 'Modal awal', value: openingCash.toRupiah),
          _MoneyLine(label: 'Penjualan tunai', value: cashSales.toRupiah),
          const Divider(height: 22),
          _MoneyLine(
            label: 'Kas seharusnya',
            value: expected.toRupiah,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  const _MoneyLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: emphasized
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                fontSize: emphasized ? 16 : 14,
              ),
            ),
          ],
        ),
      );
}

class _EmptyShiftState extends StatelessWidget {
  final bool submitting;
  final VoidCallback onOpen;
  const _EmptyShiftState({required this.submitting, required this.onOpen});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 38, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: AppTheme.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Belum ada shift aktif',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Catat modal awal untuk memantau penjualan dan selisih kas sampai shift ditutup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: submitting ? null : onOpen,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Buka shift kasir'),
              ),
            ),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: Column(
          children: [
            const Icon(Icons.sync_problem_rounded,
                color: AppTheme.warning, size: 42),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ),
          ],
        ),
      );
}

class _OpeningCashSheet extends StatefulWidget {
  const _OpeningCashSheet();

  @override
  State<_OpeningCashSheet> createState() => _OpeningCashSheetState();
}

class _OpeningCashSheetState extends State<_OpeningCashSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = _parseMoney(_controller.text);
    if (amount == null || amount < 0 || amount > 999999999999) {
      setState(() => _error = 'Masukkan modal awal yang valid.');
      return;
    }
    Navigator.pop(context, amount);
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
        title: 'Modal awal shift',
        subtitle: 'Masukkan jumlah uang fisik yang tersedia di laci kas.',
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            selectAllOnFocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              const NormalizedNumberInputFormatter(),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Modal awal',
              prefixText: 'Rp ',
              hintText: '0',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('Lanjutkan'),
            ),
          ),
        ],
      );
}

class _CloseShiftInput {
  final double actualCash;
  final String? notes;
  const _CloseShiftInput({required this.actualCash, this.notes});
}

class _CloseShiftSheet extends StatefulWidget {
  final double expectedCash;
  const _CloseShiftSheet({required this.expectedCash});

  @override
  State<_CloseShiftSheet> createState() => _CloseShiftSheetState();
}

class _CloseShiftSheetState extends State<_CloseShiftSheet> {
  final _cashController = TextEditingController();
  final _notesController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = _parseMoney(_cashController.text);
    if (amount == null || amount < 0 || amount > 999999999999) {
      setState(() => _error = 'Masukkan jumlah kas aktual yang valid.');
      return;
    }
    final notes = _notesController.text.trim();
    Navigator.pop(
      context,
      _CloseShiftInput(
        actualCash: amount,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentCash = _parseMoney(_cashController.text);
    final discrepancy =
        currentCash == null ? null : currentCash - widget.expectedCash;
    return _SheetFrame(
      title: 'Rekonsiliasi kas',
      subtitle: 'Hitung uang fisik di laci, lalu cocokkan dengan sistem.',
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: _MoneyLine(
            label: 'Kas seharusnya',
            value: widget.expectedCash.toRupiah,
            emphasized: true,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cashController,
          autofocus: true,
          selectAllOnFocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            const NormalizedNumberInputFormatter(),
          ],
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: 'Kas aktual',
            prefixText: 'Rp ',
            hintText: 'Hitung uang di laci',
            errorText: _error,
          ),
        ),
        if (discrepancy != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              discrepancy.abs() < 0.5
                  ? 'Kas sesuai'
                  : 'Selisih ${_signedMoney(discrepancy)}',
              style: TextStyle(
                color: discrepancy.abs() < 0.5
                    ? AppTheme.success
                    : AppTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _notesController,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Catatan (opsional)',
            hintText: 'Contoh: selisih untuk uang makan kurir',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _submit,
            child: const Text('Tinjau penutupan shift'),
          ),
        ),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + media.viewInsets.bottom + media.viewPadding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DialogLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _DialogLine({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

double _money(String value) => double.tryParse(value) ?? 0;

double? _parseMoney(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return double.tryParse(digits);
}

String _signedMoney(double value) {
  if (value.abs() < 0.5) return 0.0.toRupiah;
  return '${value > 0 ? '+' : '-'}${value.abs().toRupiah}';
}

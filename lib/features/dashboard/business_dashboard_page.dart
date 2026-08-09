import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../data/local/daos/finance_dao.dart';
import '../shared/polish_widgets.dart';

class BusinessDashboardPage extends ConsumerStatefulWidget {
  const BusinessDashboardPage({super.key});

  @override
  ConsumerState<BusinessDashboardPage> createState() =>
      _BusinessDashboardPageState();
}

class _BusinessDashboardPageState extends ConsumerState<BusinessDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<_DashboardData> _data;
  int? _lastDataRevision;

  DateTime get _from => DateTime(_month.year, _month.month);
  DateTime get _to => DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _data = _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_DashboardData> _loadData() async {
    final db = ref.read(databaseProvider);
    final dao = db.financeDao;
    final user = ref.read(currentUserProvider);

    if (user?.canViewAllBranches != true) {
      final outletIds = user == null
          ? [ref.read(currentOutletIdProvider)]
          : user.accessibleOutletIds;
      final branches = await dao.getBranchSummariesForOutlets(
        outletIds,
        _from,
        _to,
      );
      final trend = await dao.getDailySummariesForOutlets(
        outletIds,
        _from,
        _to,
      );
      return _DashboardData(
        branches: branches,
        trend: trend,
        isAllBranches: false,
      );
    }

    final branches = await dao.getBranchSummaries(_from, _to);
    final trend = await dao.getDailySummaries(_from, _to);
    return _DashboardData(branches: branches, trend: trend);
  }

  void _refresh() => setState(() => _data = _loadData());

  void _shiftMonth(int change) {
    setState(() {
      _month = DateTime(_month.year, _month.month + change);
      _data = _loadData();
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month.isAfter(now) ? now : _month,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Pilih bulan dashboard',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _data = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(businessDataRevisionProvider).asData?.value;
    if (revision != null && revision != _lastDataRevision) {
      _lastDataRevision = revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Dashboard Bisnis'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Catat pengeluaran',
            onPressed: _showExpenseSheet,
            icon: const Icon(Icons.add_card_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Ikhtisar'),
            Tab(text: 'Laba Rugi'),
            Tab(text: 'Cabang'),
          ],
        ),
      ),
      body: FutureBuilder<_DashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorState(onRetry: _refresh);
          }
          final data = snapshot.data!;
          return Column(
            children: [
              _MonthPicker(
                month: _month,
                onChange: _shiftMonth,
                onPick: _pickMonth,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(data: data),
                    _ProfitLossTab(
                      data: data,
                      from: _from,
                      to: _to,
                      onDeleteExpense: _deleteExpense,
                    ),
                    _BranchesTab(data: data),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showExpenseSheet,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Pengeluaran'),
      ),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    final user = ref.read(currentUserProvider);
    if (user?.isOwner != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya owner yang dapat menghapus pengeluaran.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text(
          '${expense.category} sebesar '
          '${(double.tryParse(expense.amount) ?? 0).toRupiah} akan dihapus dari laporan keuangan.',
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
    if (confirmed != true) return;

    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.syncDao.enqueue(
        tableName: 'expenses',
        recordId: expense.id,
        operation: 'delete',
        payload: {'outlet_id': expense.outletId},
      );
      await db.financeDao.deleteExpense(expense.id);
    });

    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pengeluaran berhasil dihapus.'),
        backgroundColor: AppTheme.success,
      ),
    );
    unawaited(ref.read(syncServiceProvider).syncAll());
  }

  Future<void> _showExpenseSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExpenseSheet(),
    );
    if (saved == true) _refresh();
  }
}

class _DashboardData {
  final List<FinanceSummary> branches;
  final List<FinanceSummary> trend;
  final bool isAllBranches;
  const _DashboardData({
    required this.branches,
    required this.trend,
    this.isAllBranches = true,
  });

  double get revenue => branches.fold(0, (sum, item) => sum + item.revenue);
  double get cogs => branches.fold(0, (sum, item) => sum + item.cogs);
  double get expenses => branches.fold(0, (sum, item) => sum + item.expenses);
  double get grossProfit => revenue - cogs;
  double get netProfit => grossProfit - expenses;
  int get transactions =>
      branches.fold(0, (sum, item) => sum + item.transactions);
  double get margin => revenue == 0 ? 0 : netProfit / revenue * 100;
}

class _MonthPicker extends StatelessWidget {
  final DateTime month;
  final ValueChanged<int> onChange;
  final VoidCallback onPick;
  const _MonthPicker({
    required this.month,
    required this.onChange,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: () => onChange(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 18),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _monthName(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: month.year == DateTime.now().year &&
                      month.month == DateTime.now().month
                  ? null
                  : () => onChange(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );

  String _monthName(DateTime date) {
    const names = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${names[date.month - 1]} ${date.year}';
  }
}

class _OverviewTab extends StatelessWidget {
  final _DashboardData data;
  const _OverviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final best = data.branches.isEmpty ? null : data.branches.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
      children: [
        _NetProfitHero(value: data.netProfit, margin: data.margin),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _MetricCard(
              label: 'Omzet',
              value: data.revenue.toRupiahCompact,
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              label: 'Transaksi',
              value: '${data.transactions}',
              icon: Icons.receipt_long_outlined,
              color: AppTheme.info,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _MetricCard(
              label: 'Laba kotor',
              value: data.grossProfit.toRupiahCompact,
              icon: Icons.show_chart_rounded,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              label: 'Biaya usaha',
              value: data.expenses.toRupiahCompact,
              icon: Icons.remove_circle_outline_rounded,
              color: AppTheme.danger,
            ),
          ),
        ]),
        const SizedBox(height: 22),
        const _SectionHeading('Tren omzet harian'),
        const SizedBox(height: 10),
        _TrendCard(trend: data.trend),
        const SizedBox(height: 22),
        _SectionHeading(
          data.isAllBranches ? 'Sorotan cabang' : 'Ringkasan cabang',
        ),
        const SizedBox(height: 10),
        if (best == null)
          const _EmptyCard(
            icon: Icons.storefront_outlined,
            message: 'Belum ada data cabang untuk periode ini.',
          )
        else
          _InsightCard(
            icon: Icons.emoji_events_outlined,
            color: AppTheme.gold,
            title: data.isAllBranches
                ? '${best.outletName} memimpin penjualan'
                : data.branches.length > 1
                    ? 'Cabang tugasmu bulan ini'
                    : '${best.outletName} bulan ini',
            subtitle:
                '${best.revenue.toRupiah} dari ${best.transactions} transaksi • margin bersih ${best.margin.toStringAsFixed(1)}%',
          ),
      ],
    );
  }
}

class _ProfitLossTab extends ConsumerWidget {
  final _DashboardData data;
  final DateTime from;
  final DateTime to;
  final ValueChanged<Expense> onDeleteExpense;
  const _ProfitLossTab({
    required this.data,
    required this.from,
    required this.to,
    required this.onDeleteExpense,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOutletId = ref.watch(currentOutletIdProvider);
    final isOwner = ref.watch(currentUserProvider)?.isOwner == true;
    final current =
        data.branches.where((item) => item.outletId == currentOutletId);
    final local = current.isEmpty ? null : current.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
      children: [
        const _SectionHeading('Laporan laba rugi konsolidasi'),
        const SizedBox(height: 4),
        const Text(
          'Angka dibuat otomatis dari penjualan, HPP menu, dan beban yang dicatat.',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        _ProfitLossCard(data: data),
        const SizedBox(height: 22),
        const _SectionHeading('Kesehatan finansial'),
        const SizedBox(height: 10),
        _HealthCard(data: data),
        if (local != null) ...[
          const SizedBox(height: 22),
          _SectionHeading('Daftar pengeluaran • ${local.outletName}'),
          const SizedBox(height: 10),
          FutureBuilder<List<Expense>>(
            future: ref.read(databaseProvider).financeDao.getExpenses(
                  currentOutletId,
                  from,
                  to,
                ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ModernCard(
                  child: SizedBox(
                    height: 72,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const _EmptyCard(
                  icon: Icons.cloud_off_outlined,
                  message:
                      'Daftar pengeluaran belum bisa dimuat. Buka ulang dashboard untuk mencoba lagi.',
                );
              }
              final expenses = snapshot.data ?? [];
              if (expenses.isEmpty) {
                return const _EmptyCard(
                  icon: Icons.receipt_long_outlined,
                  message: 'Belum ada pengeluaran yang dicatat bulan ini.',
                );
              }
              return ModernCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: expenses
                      .map(
                        (expense) => _ExpenseRow(
                          expense,
                          onDelete:
                              isOwner ? () => onDeleteExpense(expense) : null,
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _BranchesTab extends StatelessWidget {
  final _DashboardData data;
  const _BranchesTab({required this.data});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
        children: [
          Row(children: [
            Expanded(
              child: _SectionHeading(
                data.isAllBranches
                    ? 'Performa semua cabang'
                    : 'Performa cabang tugas',
              ),
            ),
            _StatusPill(
              icon: Icons.cloud_done_outlined,
              label: '${data.branches.length} cabang',
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            data.isAllBranches
                ? 'Bandingkan omzet, laba bersih, dan margin dalam satu tampilan.'
                : 'Manager hanya melihat cabang yang ditugaskan owner.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (data.branches.isEmpty)
            const _EmptyCard(
              icon: Icons.store_mall_directory_outlined,
              message: 'Data cabang akan muncul setelah penjualan tersinkron.',
            )
          else
            ...data.branches.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child:
                        _BranchCard(rank: entry.key + 1, branch: entry.value),
                  ),
                ),
          const SizedBox(height: 10),
          const _InsightCard(
            icon: Icons.lightbulb_outline_rounded,
            color: AppTheme.primary,
            title: 'Kontrol cabang, bukan sekadar lihat angka',
            subtitle:
                'Pantau performa konsolidasi, lalu catat biaya dari outlet aktif agar laba bersih tetap akurat.',
          ),
        ],
      );
}

class _NetProfitHero extends StatelessWidget {
  final double value;
  final double margin;
  const _NetProfitHero({required this.value, required this.margin});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.floatingShadow,
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LABA BERSIH',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8)),
                const SizedBox(height: 8),
                Text(value.toRupiah,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Margin ${margin.toStringAsFixed(1)}% bulan ini',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .86),
                        fontSize: 12)),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.insights_rounded, color: Colors.white),
          ),
        ]),
      );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => ModernCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _TrendCard extends StatelessWidget {
  final List<FinanceSummary> trend;
  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    final points = trend.length > 7 ? trend.sublist(trend.length - 7) : trend;
    final max = points.fold<double>(
        0, (max, item) => item.revenue > max ? item.revenue : max);
    if (max == 0) {
      return const _EmptyCard(
          icon: Icons.show_chart_rounded,
          message: 'Belum ada transaksi pada periode ini.');
    }
    return ModernCard(
      padding: const EdgeInsets.fromLTRB(8, 18, 14, 8),
      child: SizedBox(
        height: 185,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: max * 1.2,
          gridData: FlGridData(
              show: true, drawVerticalLine: false, horizontalInterval: max / 3),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: max / 3,
              getTitlesWidget: (value, _) => Text(
                  value.toRupiahCompact.replaceFirst('Rp ', ''),
                  style: const TextStyle(
                      fontSize: 9, color: AppTheme.textSecondary)),
            )),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(points[index].outletName,
                      style: const TextStyle(
                          fontSize: 9, color: AppTheme.textSecondary)),
                );
              },
            )),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].revenue)
              ],
              isCurved: true,
              color: AppTheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true, color: AppTheme.primary.withValues(alpha: .12)),
            ),
          ],
        )),
      ),
    );
  }
}

class _ProfitLossCard extends StatelessWidget {
  final _DashboardData data;
  const _ProfitLossCard({required this.data});

  @override
  Widget build(BuildContext context) => ModernCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          _MoneyLine('Pendapatan penjualan', data.revenue, AppTheme.primary),
          const Divider(),
          _MoneyLine('Harga pokok penjualan (HPP)', -data.cogs,
              AppTheme.textSecondary),
          _MoneyLine('Laba kotor', data.grossProfit, AppTheme.success,
              bold: true),
          const Divider(),
          _MoneyLine('Beban operasional', -data.expenses, AppTheme.danger),
          Container(height: 1, color: AppTheme.borderColor),
          _MoneyLine('LABA BERSIH', data.netProfit,
              data.netProfit >= 0 ? AppTheme.success : AppTheme.danger,
              bold: true, large: true),
        ]),
      );
}

class _MoneyLine extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool bold;
  final bool large;
  const _MoneyLine(this.label, this.amount, this.color,
      {this.bold = false, this.large = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: large ? 14 : 13,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(amount.toRupiah,
              style: TextStyle(
                  fontSize: large ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      );
}

class _HealthCard extends StatelessWidget {
  final _DashboardData data;
  const _HealthCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cogsRatio = data.revenue == 0 ? 0.0 : data.cogs / data.revenue * 100;
    final expenseRatio =
        data.revenue == 0 ? 0.0 : data.expenses / data.revenue * 100;
    return ModernCard(
      child: Column(children: [
        _RatioRow('Margin laba bersih', data.margin, AppTheme.success),
        const SizedBox(height: 14),
        _RatioRow('Porsi HPP', cogsRatio, AppTheme.warning),
        const SizedBox(height: 14),
        _RatioRow('Porsi biaya operasional', expenseRatio, AppTheme.danger),
      ]),
    );
  }
}

class _RatioRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _RatioRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          Text('${value.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
              value: value.clamp(0, 100).toDouble() / 100,
              minHeight: 7,
              color: color,
              backgroundColor: color.withValues(alpha: .12)),
        ),
      ]);
}

class _BranchCard extends StatelessWidget {
  final int rank;
  final FinanceSummary branch;
  const _BranchCard({required this.rank, required this.branch});

  @override
  Widget build(BuildContext context) => ModernCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: rank == 1 ? AppTheme.goldLight : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10)),
            child: Text('#$rank',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: rank == 1
                        ? const Color(0xFF8C5A00)
                        : AppTheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(branch.outletName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${branch.transactions} transaksi • margin ${branch.margin.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _BranchAmount(
                          label: 'Omzet',
                          amount: branch.revenue,
                          color: AppTheme.primary)),
                  Expanded(
                      child: _BranchAmount(
                          label: 'Laba bersih',
                          amount: branch.netProfit,
                          color: branch.netProfit >= 0
                              ? AppTheme.success
                              : AppTheme.danger)),
                ]),
              ])),
        ]),
      );
}

class _BranchAmount extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  const _BranchAmount(
      {required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 2),
        Text(amount.toRupiahCompact,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]);
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onDelete;
  const _ExpenseRow(this.expense, {this.onDelete});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.remove_circle_outline_rounded,
              size: 18, color: AppTheme.danger),
        ),
        title: Text(expense.category,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text(
            expense.description ?? DateHelper.formatDate(expense.occurredAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (double.tryParse(expense.amount) ?? 0).toRupiah,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.danger,
                fontSize: 12,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Hapus pengeluaran',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.danger,
                  size: 20,
                ),
              ),
            ],
          ],
        ),
      );
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _InsightCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .18))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppTheme.textSecondary)),
              ])),
        ]),
      );
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => ModernCard(
        child: Center(
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Icon(icon, color: AppTheme.textSecondary, size: 28),
                  const SizedBox(height: 8),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ]))),
      );
}

class _SectionHeading extends StatelessWidget {
  final String title;
  const _SectionHeading(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800));
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatusPill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppTheme.iconCompact, color: AppTheme.success),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success)),
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            color: AppTheme.danger, size: 36),
        const SizedBox(height: 10),
        const Text('Dashboard belum bisa dimuat.'),
        TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ]));
}

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet();
  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = 'Operasional';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final raw = _amount.text.replaceAll(RegExp(r'[^0-9]'), '');
    final user = ref.read(currentUserProvider);
    final currentOutletId = ref.read(currentOutletIdProvider);
    final accessibleOutletIds = user?.accessibleOutletIds ?? [currentOutletId];
    final String outletId = user?.canViewAllBranches == true
        ? currentOutletId
        : accessibleOutletIds.contains(currentOutletId)
            ? currentOutletId
            : accessibleOutletIds.first;
    await ref
        .read(databaseProvider)
        .financeDao
        .addExpense(ExpensesCompanion.insert(
          id: IdGen.uuid(),
          outletId: outletId,
          category: _category,
          amount: raw,
          description:
              Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
          occurredAt: DateTime.now(),
        ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          bottomSheetSafePadding(context),
        ),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 18),
              const Row(children: [
                Icon(Icons.add_card_rounded, color: AppTheme.primary),
                SizedBox(width: 9),
                Text('Catat pengeluaran',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))
              ]),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: const [
                  'Operasional',
                  'Gaji',
                  'Sewa',
                  'Utilitas',
                  'Pemasaran',
                  'Lainnya'
                ]
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                selectAllOnFocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Nominal', prefixText: 'Rp '),
                validator: (value) =>
                    (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').isEmpty
                        ? 'Nominal wajib diisi'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _note,
                  decoration:
                      const InputDecoration(labelText: 'Keterangan (opsional)'),
                  maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text(
                          _saving ? 'Menyimpan...' : 'Simpan pengeluaran'))),
            ]),
          ),
        ),
      );
}

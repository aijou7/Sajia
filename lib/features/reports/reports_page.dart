import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../shared/polish_widgets.dart';

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String>? _reportOutletIds(WidgetRef ref, {bool listen = true}) {
  final user =
      listen ? ref.watch(currentUserProvider) : ref.read(currentUserProvider);

  if (user?.canViewAllBranches == true) return null;
  if (user != null) return user.accessibleOutletIds;

  return listen
      ? [ref.watch(currentOutletIdProvider)]
      : [ref.read(currentOutletIdProvider)];
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  bool _isMonthly = false;

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final outletIds = _reportOutletIds(ref, listen: false);
    final db = ref.read(databaseProvider);

    // Ambil data
    final summary =
        await db.orderDao.getSalesSummaryForScope(outletIds, _from, _to);
    final products =
        await db.orderDao.getTopProductsForScope(outletIds, _from, _to);
    final categories =
        await db.orderDao.getSalesByCategoryForScope(outletIds, _from, _to);

    final revenue = _asDouble(summary['totalRevenue']);
    final cash = _asDouble(summary['totalCash']);
    final qris = _asDouble(summary['totalQris']);
    final count = _asInt(summary['orderCount']);
    final avg = _asDouble(summary['avgOrderValue']);

    // Buat PDF
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(AppBrand.name,
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue700)),
                  pw.SizedBox(height: 3),
                  pw.Text('LAPORAN PENJUALAN',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Periode: $_periodLabel',
                      style: const pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey600)),
                ],
              ),
              pw.Text(
                DateHelper.formatDate(DateTime.now()),
                style:
                    const pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
              ),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.grey300),
          pw.SizedBox(height: 8),

          // Ringkasan
          pw.Text('RINGKASAN',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Omzet',
                        style: const pw.TextStyle(
                            fontSize: 11, color: PdfColors.grey600)),
                    pw.SizedBox(height: 4),
                    pw.Text(revenue.toRupiah,
                        style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('$count Transaksi',
                        style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 4),
                    pw.Text('Rata-rata: ${avg.toRupiah}',
                        style: const pw.TextStyle(
                            fontSize: 11, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Metode pembayaran
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Tunai',
                          style: const pw.TextStyle(
                              fontSize: 11, color: PdfColors.grey500)),
                      pw.SizedBox(height: 4),
                      pw.Text(cash.toRupiah,
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green800)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('QRIS',
                          style: const pw.TextStyle(
                              fontSize: 11, color: PdfColors.grey500)),
                      pw.SizedBox(height: 4),
                      pw.Text(qris.toRupiah,
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // Top produk
          if (products.isNotEmpty) ...[
            pw.Text('TOP PRODUK',
                style:
                    pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FixedColumnWidth(32),
                1: const pw.FlexColumnWidth(),
                2: const pw.FixedColumnWidth(70),
                3: const pw.FixedColumnWidth(90),
              },
              children: [
                // Header tabel
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('#',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Produk',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Terjual',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Pendapatan',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                // Rows
                ...products.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final isEven = i % 2 == 0;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${i + 1}',
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(p['name'] as String,
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${_asDouble(p['qty']).toInt()}x',
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(_asDouble(p['revenue']).toRupiah,
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],

          if (categories.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('PENJUALAN PER KATEGORI',
                style:
                    pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FlexColumnWidth(),
                1: const pw.FixedColumnWidth(62),
                2: const pw.FixedColumnWidth(62),
                3: const pw.FixedColumnWidth(92),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    for (final label in [
                      'Kategori',
                      'Produk',
                      'Terjual',
                      'Pendapatan'
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(label,
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                  ],
                ),
                ...categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final category = entry.value;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: index.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(category['name'] as String,
                            style: const pw.TextStyle(fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${_asInt(category['productCount'])}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${_asDouble(category['qty']).toInt()}x',
                            style: const pw.TextStyle(fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(_asDouble(category['revenue']).toRupiah,
                            style: const pw.TextStyle(fontSize: 10)),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],

          pw.SizedBox(height: 30),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Text(
            'Digenerate otomatis oleh ${AppBrand.name} - ${DateTime.now().toString().substring(0, 19)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey400),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    // Preview + share
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Laporan_$_periodLabel.pdf',
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime get _from => _isMonthly
      ? DateHelper.startOfMonth(_selectedDate)
      : DateHelper.startOfDay(_selectedDate);

  DateTime get _to => _isMonthly
      ? DateHelper.endOfMonth(_selectedDate)
      : DateHelper.endOfDay(_selectedDate);

  String get _periodLabel => _isMonthly
      ? '${_selectedDate.month}/${_selectedDate.year}'
      : DateHelper.formatDate(_selectedDate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(
            onPressed: () => _exportPdf(context, ref),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            color: AppTheme.primary,
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PeriodToggle(
                  label: 'Harian',
                  selected: !_isMonthly,
                  onTap: () => setState(() => _isMonthly = false),
                ),
                _PeriodToggle(
                  label: 'Bulanan',
                  selected: _isMonthly,
                  onTap: () => setState(() => _isMonthly = true),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ringkasan'),
            Tab(text: 'Produk'),
            Tab(text: 'Kategori'),
          ],
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: AppTheme.primary,
        ),
      ),
      body: Column(
        children: [
          _DateNavigator(
            label: _periodLabel,
            onPrev: () => setState(() {
              _selectedDate = _isMonthly
                  ? DateTime(_selectedDate.year, _selectedDate.month - 1)
                  : _selectedDate.subtract(const Duration(days: 1));
            }),
            onNext: () {
              final next = _isMonthly
                  ? DateTime(_selectedDate.year, _selectedDate.month + 1)
                  : _selectedDate.add(const Duration(days: 1));
              if (next.isBefore(DateTime.now().add(const Duration(days: 1)))) {
                setState(() => _selectedDate = next);
              }
            },
            onToday: () => setState(() => _selectedDate = DateTime.now()),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SummaryTab(
                  key: ValueKey('summary-$_periodLabel'),
                  from: _from,
                  to: _to,
                ),
                _ProductTab(
                  key: ValueKey('product-$_periodLabel'),
                  from: _from,
                  to: _to,
                ),
                _CategoryReportTab(
                  key: ValueKey('category-$_periodLabel'),
                  from: _from,
                  to: _to,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── DATE NAVIGATOR ────────────────────────────────────────────
class _DateNavigator extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const _DateNavigator({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onToday,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ── SUMMARY TAB ───────────────────────────────────────────────
class _ReportEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ReportEmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        pageBottomSafePadding(context),
      ),
      children: [
        ModernCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 28),
          child: EmptyStateView(
            icon: icon,
            title: title,
            subtitle: subtitle,
          ),
        ),
      ],
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  final DateTime from;
  final DateTime to;

  const _SummaryTab({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletIds = _reportOutletIds(ref);
    final db = ref.watch(databaseProvider);

    return FutureBuilder<Map<String, dynamic>>(
      future: db.orderDao.getSalesSummaryForScope(outletIds, from, to),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const _ReportEmptyView(
            icon: Icons.error_outline_rounded,
            title: 'Laporan belum bisa dimuat',
            subtitle:
                'Coba buka ulang halaman ini. Kalau masih kosong, cek data outlet aktif.',
          );
        }

        final data = snapshot.data!;
        final revenue = _asDouble(data['totalRevenue']);
        final cash = _asDouble(data['totalCash']);
        final qris = _asDouble(data['totalQris']);
        final count = _asInt(data['orderCount']);
        final avg = _asDouble(data['avgOrderValue']);

        if (count == 0) {
          return const _ReportEmptyView(
            icon: Icons.insert_chart_outlined_rounded,
            title: 'Belum ada data ringkasan',
            subtitle:
                'Ringkasan omzet, transaksi, dan metode pembayaran akan muncul setelah ada transaksi lunas di periode ini.',
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            pageBottomSafePadding(context),
          ),
          children: [
            _HeroCard(
              label: 'Total Omzet',
              value: revenue.toRupiah,
              icon: Icons.trending_up_rounded,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        label: 'Transaksi',
                        value: '$count',
                        icon: Icons.receipt_long_outlined,
                        color: AppTheme.info)),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatCard(
                        label: 'Rata-rata',
                        value: avg.toRupiahCompact,
                        icon: Icons.analytics_outlined,
                        color: AppTheme.warning)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        label: 'Tunai',
                        value: cash.toRupiahCompact,
                        icon: Icons.payments_outlined,
                        color: AppTheme.success)),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatCard(
                        label: 'QRIS',
                        value: qris.toRupiahCompact,
                        icon: Icons.qr_code_rounded,
                        color: AppTheme.qris)),
              ],
            ),
            const SizedBox(height: 20),
            if (revenue > 0) ...[
              const _SectionTitle('Metode Pembayaran'),
              const SizedBox(height: 12),
              _PaymentChart(cash: cash, qris: qris, total: revenue),
              const SizedBox(height: 20),
            ],
            const _SectionTitle('Penjualan per Jam'),
            const SizedBox(height: 12),
            _HourlyChart(from: from, to: to),
          ],
        );
      },
    );
  }
}

// ── PRODUCT TAB ───────────────────────────────────────────────
class _ProductTab extends ConsumerWidget {
  final DateTime from;
  final DateTime to;

  const _ProductTab({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletIds = _reportOutletIds(ref);
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.orderDao.getTopProductsForScope(outletIds, from, to),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const _ReportEmptyView(
            icon: Icons.error_outline_rounded,
            title: 'Data produk belum bisa dimuat',
            subtitle: 'Coba buka ulang halaman ini atau cek outlet aktif.',
          );
        }

        final products = snapshot.data!;

        if (products.isEmpty) {
          return const _ReportEmptyView(
            icon: Icons.fastfood_outlined,
            title: 'Belum ada data penjualan',
            subtitle: 'Produk terlaris akan muncul setelah ada transaksi.',
          );
        }

        final maxQty = _asDouble(products.first['qty']);

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final p = products[i];
            final qty = _asDouble(p['qty']);
            final revenue = _asDouble(p['revenue']);
            final ratio = maxQty > 0 ? qty / maxQty : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.subtleBorder),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: i < 3
                              ? [
                                  AppTheme.warning,
                                  const Color(0xFF9CA3AF),
                                  const Color(0xFFCD7F32)
                                ][i]
                                  .withValues(alpha: 0.15)
                              : const Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: i < 3
                                    ? [
                                        AppTheme.warning,
                                        const Color(0xFF6B7280),
                                        const Color(0xFFCD7F32)
                                      ][i]
                                    : const Color(0xFF9CA3AF),
                              )),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(p['name'] as String,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${qty.toInt()} terjual',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                          Text(revenue.toRupiahCompact,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: const Color(0xFFF3F4F6),
                      color:
                          AppTheme.primary.withValues(alpha: 0.4 + ratio * 0.6),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── CATEGORY REPORT TAB ───────────────────────────────────────
class _CategoryReportTab extends ConsumerWidget {
  final DateTime from;
  final DateTime to;

  const _CategoryReportTab({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletIds = _reportOutletIds(ref);
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.orderDao.getSalesByCategoryForScope(outletIds, from, to),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const _ReportEmptyView(
            icon: Icons.error_outline_rounded,
            title: 'Laporan kategori belum bisa dimuat',
            subtitle: 'Coba buka ulang halaman ini atau cek outlet aktif.',
          );
        }

        final categories = snapshot.data!;
        if (categories.isEmpty) {
          return const _ReportEmptyView(
            icon: Icons.category_outlined,
            title: 'Belum ada data per kategori',
            subtitle:
                'Pemisahan penjualan per kategori akan muncul setelah ada transaksi lunas.',
          );
        }

        final totalRevenue = categories.fold<double>(
          0,
          (sum, category) => sum + _asDouble(category['revenue']),
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            pageBottomSafePadding(context),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.category_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Omzet per Kategori',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          totalRevenue.toRupiah,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${categories.length} kategori',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...categories.map((category) {
              final revenue = _asDouble(category['revenue']);
              final qty = _asDouble(category['qty']);
              final productCount = _asInt(category['productCount']);
              final contribution =
                  totalRevenue > 0 ? revenue / totalRevenue : 0.0;
              Color categoryColor;
              try {
                categoryColor = Color(int.parse(
                  (category['colorHex'] as String? ?? '#6B7280')
                      .replaceFirst('#', '0xFF'),
                ));
              } catch (_) {
                categoryColor = AppTheme.primary;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.subtleBorder),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.label_rounded,
                            color: categoryColor,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category['name'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$productCount produk • ${qty.toInt()} terjual',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              revenue.toRupiahCompact,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${(contribution * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: contribution.clamp(0.0, 1.0).toDouble(),
                        minHeight: 7,
                        backgroundColor: const Color(0xFFF3F4F6),
                        color: categoryColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── PAYMENT CHART ─────────────────────────────────────────────
class _PaymentChart extends StatelessWidget {
  final double cash;
  final double qris;
  final double total;

  const _PaymentChart(
      {required this.cash, required this.qris, required this.total});

  @override
  Widget build(BuildContext context) {
    final other = (total - cash - qris).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                if (cash > 0)
                  PieChartSectionData(
                      value: cash,
                      color: AppTheme.success,
                      title: '',
                      radius: 30),
                if (qris > 0)
                  PieChartSectionData(
                      value: qris, color: AppTheme.qris, title: '', radius: 30),
                if (other > 0)
                  PieChartSectionData(
                      value: other,
                      color: AppTheme.info,
                      title: '',
                      radius: 30),
              ],
            )),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cash > 0)
                  _LegendItem(
                      color: AppTheme.success,
                      label: 'Tunai',
                      value: cash.toRupiahCompact,
                      percent: total > 0 ? (cash / total * 100).toInt() : 0),
                if (qris > 0) ...[
                  const SizedBox(height: 8),
                  _LegendItem(
                      color: AppTheme.qris,
                      label: 'QRIS',
                      value: qris.toRupiahCompact,
                      percent: total > 0 ? (qris / total * 100).toInt() : 0),
                ],
                if (other > 0) ...[
                  const SizedBox(height: 8),
                  _LegendItem(
                      color: AppTheme.info,
                      label: 'Transfer',
                      value: other.toRupiahCompact,
                      percent: total > 0 ? (other / total * 100).toInt() : 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final int percent;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
        Text('$percent%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }
}

// ── HOURLY CHART ──────────────────────────────────────────────
class _HourlyChart extends ConsumerWidget {
  final DateTime from;
  final DateTime to;

  const _HourlyChart({required this.from, required this.to});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletIds = _reportOutletIds(ref);
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<Order>>(
      future: _getOrders(db, outletIds, from, to),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final orders = snapshot.data!.where((o) => o.status == 'paid').toList();
        final hourlyRevenue = List<double>.filled(24, 0);
        for (final o in orders) {
          if (o.paidAt != null) {
            hourlyRevenue[o.paidAt!.hour] += double.tryParse(o.total) ?? 0;
          }
        }

        final operationalHours = List.generate(17, (i) => i + 7);
        final maxVal = operationalHours
            .map((h) => hourlyRevenue[h])
            .fold(0.0, (a, b) => a > b ? a : b);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: SizedBox(
            height: 160,
            child: maxVal == 0
                ? Center(
                    child: Text('Belum ada transaksi',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 13)))
                : BarChart(BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxVal * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, rod, __) {
                          final hour = operationalHours[group.x];
                          if (rod.toY == 0) return null;
                          return BarTooltipItem(
                            '${hour.toString().padLeft(2, '0')}:00\n${rod.toY.toRupiahCompact}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            final hour = operationalHours[value.toInt()];
                            if (hour % 3 != 0) return const SizedBox();
                            return Text('${hour}j',
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xFF9CA3AF)));
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxVal / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0xFFF3F4F6), strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(operationalHours.length, (i) {
                      final val = hourlyRevenue[operationalHours[i]];
                      return BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: val,
                          color: val > 0
                              ? AppTheme.primary
                              : const Color(0xFFF3F4F6),
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ]);
                    }),
                  )),
          ),
        );
      },
    );
  }

  Future<List<Order>> _getOrders(AppDatabase db, List<String>? outletIds,
      DateTime from, DateTime to) async {
    if (outletIds != null && outletIds.isEmpty) return [];
    final query = db.select(db.orders);
    if (outletIds != null) {
      query.where((o) => o.outletId.isIn(outletIds));
    }
    final all = await query.get();
    return all
        .where((o) => !o.createdAt.isBefore(from) && !o.createdAt.isAfter(to))
        .toList();
  }
}

// ── REUSABLE WIDGETS ──────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _HeroCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)));
}

class _PeriodToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : const Color(0xFF6B7280),
            )),
      ),
    );
  }
}

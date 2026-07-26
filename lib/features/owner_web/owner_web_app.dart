import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';

class OwnerWebApp extends StatelessWidget {
  const OwnerWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '${AppBrand.name} Owner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _OwnerPortal(),
      );
}

class _OwnerPortal extends StatelessWidget {
  const _OwnerPortal();

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          Supabase.instance.client.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final session = snapshot.data?.session;
          return session == null
              ? const _OwnerSignInPage()
              : _OwnerWorkspace(email: session.user.email ?? 'Owner');
        },
      );
}

class _OwnerSignInPage extends StatefulWidget {
  const _OwnerSignInPage();

  @override
  State<_OwnerSignInPage> createState() => _OwnerSignInPageState();
}

class _OwnerSignInPageState extends State<_OwnerSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Email dan kata sandi wajib diisi.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Tidak dapat menghubungkan ke server.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 28),
                      const Text(
                        'Masuk ke dashboard owner',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pantau performa seluruh cabang dari satu tempat.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email owner',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        onSubmitted: (_) => _signIn(),
                        decoration: const InputDecoration(
                          labelText: 'Kata sandi',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.danger, fontSize: 12)),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _loading ? null : _signIn,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(_loading ? 'Memeriksa akun...' : 'Masuk'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _OwnerWorkspace extends StatefulWidget {
  final String email;
  const _OwnerWorkspace({required this.email});

  @override
  State<_OwnerWorkspace> createState() => _OwnerWorkspaceState();
}

class _OwnerWorkspaceState extends State<_OwnerWorkspace> {
  late Future<_OwnerDashboardData> _dashboard;

  @override
  void initState() {
    super.initState();
    _dashboard = _loadDashboard();
  }

  Future<_OwnerDashboardData> _loadDashboard() async {
    final client = Supabase.instance.client;
    await client.rpc('ensure_owner_organization');
    final now = DateTime.now();
    final from = DateTime(now.year, now.month);
    final to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final response = await client.rpc('get_owner_dashboard', params: {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    final outletResponse = await client.rpc('get_owner_outlets');
    return _OwnerDashboardData.fromJson(
      Map<String, dynamic>.from(response as Map),
      outlets: (outletResponse as List? ?? const [])
          .map((row) => _OwnerOutletData.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(),
    );
  }

  void _reload() => setState(() => _dashboard = _loadDashboard());

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(
          children: [
            Container(
              width: 250,
              color: AppTheme.primaryDeep,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandHeader(dark: true),
                  const SizedBox(height: 48),
                  const _MenuItem(
                      icon: Icons.dashboard_rounded, label: 'Dashboard'),
                  const _MenuItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Laporan keuangan'),
                  const _MenuItem(
                      icon: Icons.storefront_outlined, label: 'Cabang'),
                  const Spacer(),
                  Text(widget.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .7),
                          fontSize: 12)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: Supabase.instance.client.auth.signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Keluar'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: .9)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_OwnerDashboardData>(
                future: _dashboard,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _CloudDashboardSetup(onRetry: _reload);
                  }
                  return _OwnerDashboard(
                    data: snapshot.data!,
                    onRefresh: _reload,
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _CloudDashboardSetup extends StatelessWidget {
  final VoidCallback onRetry;
  const _CloudDashboardSetup({required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.all(40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_sync_outlined,
                          color: AppTheme.primary, size: 28),
                    ),
                    const SizedBox(height: 18),
                    const Text('Dashboard cloud belum siap dibaca',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'Jalankan migration Owner Portal di Supabase SQL Editor, '
                      'lalu masuk dengan email Supabase Auth yang sama dengan '
                      'owner_email pada data outlet.',
                      style:
                          TextStyle(height: 1.5, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    const _SetupPoint(
                      number: '1',
                      text:
                          'Jalankan file migration 20260623_owner_portal.sql.',
                    ),
                    const _SetupPoint(
                      number: '2',
                      text:
                          'Pastikan email owner di Auth sama dengan data outlet.',
                    ),
                    const _SetupPoint(
                      number: '3',
                      text: 'Tekan muat ulang setelah konfigurasi selesai.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Muat ulang dashboard'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _OwnerDashboardData {
  final double revenue;
  final double cogs;
  final double expenses;
  final int transactions;
  final List<_BranchData> branches;
  final List<_OwnerOutletData> outlets;

  const _OwnerDashboardData({
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.transactions,
    required this.branches,
    required this.outlets,
  });

  factory _OwnerDashboardData.fromJson(
    Map<String, dynamic> json, {
    required List<_OwnerOutletData> outlets,
  }) {
    final rawBranches = (json['branches'] as List? ?? const [])
        .map((branch) =>
            _BranchData.fromJson(Map<String, dynamic>.from(branch as Map)))
        .toList();
    return _OwnerDashboardData(
      revenue: _asDouble(json['revenue']),
      cogs: _asDouble(json['cogs']),
      expenses: _asDouble(json['expenses']),
      transactions: _asDouble(json['transactions']).toInt(),
      branches: rawBranches,
      outlets: outlets,
    );
  }

  double get grossProfit => revenue - cogs;
  double get netProfit => grossProfit - expenses;
  double get margin => revenue == 0 ? 0 : netProfit / revenue * 100;
  int get cloudOutletCount => outlets.where((outlet) => outlet.isCloud).length;
  int get proOutletCount => outlets.where((outlet) => outlet.isPro).length;
}

class _BranchData {
  final String name;
  final double revenue;
  final double netProfit;
  final int transactions;

  const _BranchData({
    required this.name,
    required this.revenue,
    required this.netProfit,
    required this.transactions,
  });

  factory _BranchData.fromJson(Map<String, dynamic> json) => _BranchData(
        name: json['outlet_name'] as String? ?? 'Outlet',
        revenue: _asDouble(json['revenue']),
        netProfit: _asDouble(json['net_profit']),
        transactions: _asDouble(json['transactions']).toInt(),
      );
}

class _OwnerOutletData {
  final String id;
  final String name;
  final String? address;
  final String licenseKey;
  final DateTime? cloudExpiry;

  const _OwnerOutletData({
    required this.id,
    required this.name,
    required this.address,
    required this.licenseKey,
    required this.cloudExpiry,
  });

  factory _OwnerOutletData.fromJson(Map<String, dynamic> json) =>
      _OwnerOutletData(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Outlet',
        address: json['address'] as String?,
        licenseKey: (json['license_key'] as String? ?? 'FREE').toUpperCase(),
        cloudExpiry: DateTime.tryParse(json['cloud_expiry']?.toString() ?? ''),
      );

  bool get isPro => licenseKey == 'PRO';
  bool get isCloud =>
      isPro && cloudExpiry != null && cloudExpiry!.isAfter(DateTime.now());
  String get planLabel => isCloud
      ? 'Cloud'
      : isPro
          ? 'Pro'
          : 'Free';
}

double _asDouble(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

class _OwnerDashboard extends StatelessWidget {
  final _OwnerDashboardData data;
  final VoidCallback onRefresh;
  const _OwnerDashboard({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.all(40),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ringkasan bisnis',
                                style: TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w800)),
                            SizedBox(height: 5),
                            Text('Periode bulan berjalan • seluruh cabang',
                                style:
                                    TextStyle(color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Muat ulang',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ]),
                    const SizedBox(height: 26),
                    _NetProfitCard(data: data),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Omzet',
                          value: _rupiah(data.revenue),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Transaksi',
                          value: '${data.transactions}',
                          icon: Icons.receipt_long_outlined,
                          color: AppTheme.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Laba kotor',
                          value: _rupiah(data.grossProfit),
                          icon: Icons.trending_up_rounded,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Beban usaha',
                          value: _rupiah(data.expenses),
                          icon: Icons.remove_circle_outline_rounded,
                          color: AppTheme.danger,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Cabang terdaftar',
                          value: '${data.outlets.length}',
                          icon: Icons.storefront_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Cabang Cloud',
                          value: '${data.cloudOutletCount}',
                          icon: Icons.cloud_done_outlined,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Cabang Pro',
                          value: '${data.proOutletCount}',
                          icon: Icons.workspace_premium_outlined,
                          color: AppTheme.gold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Cabang Free',
                          value: '${data.outlets.length - data.proOutletCount}',
                          icon: Icons.sell_outlined,
                          color: AppTheme.warning,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 30),
                    const Text('Status cabang & paket',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    if (data.outlets.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                                'Belum ada outlet terhubung ke owner ini.',
                                style:
                                    TextStyle(color: AppTheme.textSecondary)),
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: data.outlets
                              .map((outlet) => _OutletStatusRow(outlet: outlet))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 30),
                    const Text('Performa cabang',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    if (data.branches.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                                'Belum ada cabang atau transaksi pada periode ini.',
                                style:
                                    TextStyle(color: AppTheme.textSecondary)),
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: data.branches
                              .asMap()
                              .entries
                              .map((entry) => _BranchRow(
                                  rank: entry.key + 1, branch: entry.value))
                              .toList(),
                        ),
                      ),
                  ]),
            ),
          ),
        ),
      );
}

class _NetProfitCard extends StatelessWidget {
  final _OwnerDashboardData data;
  const _NetProfitCard({required this.data});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LABA BERSIH',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              const SizedBox(height: 8),
              Text(_rupiah(data.netProfit),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text('Margin ${data.margin.toStringAsFixed(1)}% bulan ini',
                  style: TextStyle(color: Colors.white.withValues(alpha: .85))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.insights_rounded,
                color: Colors.white, size: 30),
          ),
        ]),
      );
}

class _DashboardMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 18),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ]),
        ),
      );
}

class _BranchRow extends StatelessWidget {
  final int rank;
  final _BranchData branch;
  const _BranchRow({required this.rank, required this.branch});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          backgroundColor:
              rank == 1 ? AppTheme.goldLight : AppTheme.primaryLight,
          child: Text('$rank',
              style: TextStyle(
                  color: rank == 1 ? AppTheme.warning : AppTheme.primary,
                  fontWeight: FontWeight.w800)),
        ),
        title: Text(branch.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${branch.transactions} transaksi'),
        trailing:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_rupiah(branch.revenue),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('Laba ${_rupiah(branch.netProfit)}',
              style: TextStyle(fontSize: 11, color: AppTheme.success)),
        ]),
      );
}

class _OutletStatusRow extends StatelessWidget {
  final _OwnerOutletData outlet;
  const _OutletStatusRow({required this.outlet});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          backgroundColor:
              outlet.isCloud ? AppTheme.primaryLight : AppTheme.goldLight,
          child: Icon(
            outlet.isCloud
                ? Icons.cloud_done_outlined
                : outlet.isPro
                    ? Icons.workspace_premium_outlined
                    : Icons.sell_outlined,
            color: outlet.isCloud ? AppTheme.primary : AppTheme.warning,
            size: 19,
          ),
        ),
        title: Text(outlet.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(outlet.address ?? 'Alamat belum diisi'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(outlet.planLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: outlet.isCloud
                      ? AppTheme.success
                      : outlet.isPro
                          ? AppTheme.gold
                          : AppTheme.warning,
                )),
            if (outlet.cloudExpiry != null)
              Text(
                'Cloud s/d ${DateFormat('d MMM y', 'id_ID').format(outlet.cloudExpiry!)}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
          ],
        ),
      );
}

String _rupiah(double value) => NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(value);

class _BrandHeader extends StatelessWidget {
  final bool dark;
  const _BrandHeader({this.dark = false});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                dark ? Colors.white.withValues(alpha: .15) : AppTheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('S',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppBrand.name,
              style: TextStyle(
                  color: dark ? Colors.white : AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          Text('OWNER PORTAL',
              style: TextStyle(
                  color: dark
                      ? Colors.white.withValues(alpha: .62)
                      : AppTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8)),
        ]),
      ]);
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, color: Colors.white.withValues(alpha: .85), size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .9), fontSize: 13)),
        ]),
      );
}

class _SetupPoint extends StatelessWidget {
  final String number;
  final String text;
  const _SetupPoint({required this.number, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppTheme.primaryLight,
            child: Text(number,
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ]),
      );
}

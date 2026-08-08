import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand.dart';
import '../../core/onboarding_service.dart';
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
  final _otp = TextEditingController();
  bool _loading = false;
  bool _codeSent = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(Duration duration) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = duration.inSeconds.clamp(1, 3600));
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    final service = OnboardingService();
    final email = service.normalizeEmail(_email.text);
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Masukkan email owner yang valid.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _email.text = email;
      _otp.clear();
    });
    final result = await service.sendOtp(email, shouldCreateUser: false);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case OtpResult.sent:
        _startCooldown(OnboardingService.otpCooldown);
        setState(() => _codeSent = true);
      case OtpResult.cooldown || OtpResult.rateLimited:
        final retry = service.lastOtpRetryAfter ??
            await service.otpCooldownRemaining(email);
        if (!mounted) return;
        _startCooldown(
            retry > Duration.zero ? retry : OnboardingService.otpCooldown);
        setState(() {
          _codeSent = true;
          _error = 'Tunggu sebentar sebelum meminta kode baru.';
        });
      case OtpResult.accountNotFound:
        setState(() => _error =
            'Email ini belum terdaftar sebagai owner Sajia. Daftar melalui aplikasi terlebih dahulu.');
      case OtpResult.networkUnavailable:
        setState(() =>
            _error = 'Tidak dapat terhubung. Periksa internet lalu coba lagi.');
      case OtpResult.failed:
        setState(() => _error =
            'Kode OTP belum dapat dikirim. Coba lagi atau hubungi support.');
    }
  }

  Future<void> _verifyCode() async {
    if (_otp.text.trim().length != 6) {
      setState(() => _error = 'Masukkan 6 digit kode OTP.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await OnboardingService().verifyOtp(
      _email.text,
      _otp.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == OtpVerifyResult.success) return;
    setState(() {
      _error = switch (result) {
        OtpVerifyResult.expired =>
          'Kode kedaluwarsa. Kirim kode baru lalu coba lagi.',
        OtpVerifyResult.rateLimited =>
          'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.',
        OtpVerifyResult.networkUnavailable =>
          'Tidak dapat terhubung. Periksa internet lalu coba lagi.',
        OtpVerifyResult.failed =>
          'Verifikasi belum dapat dilakukan. Coba lagi.',
        _ => 'Kode OTP tidak valid. Gunakan kode terbaru dari email.',
      };
    });
  }

  void _changeEmail() {
    _resendTimer?.cancel();
    setState(() {
      _codeSent = false;
      _resendSeconds = 0;
      _otp.clear();
      _error = null;
    });
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
                        'Pantau performa seluruh cabang dengan email owner yang sama seperti di aplikasi.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _email,
                        enabled: !_codeSent && !_loading,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendCode(),
                        decoration: const InputDecoration(
                          labelText: 'Email owner',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otp,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _verifyCode(),
                          decoration: const InputDecoration(
                            labelText: 'Kode OTP 6 digit',
                            prefixIcon: Icon(Icons.password_rounded),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.danger, fontSize: 12)),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _loading
                            ? null
                            : (_codeSent ? _verifyCode : _sendCode),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _loading
                                ? 'Memproses...'
                                : (_codeSent
                                    ? 'Verifikasi & masuk'
                                    : 'Kirim kode OTP'),
                          ),
                        ),
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _loading || _resendSeconds > 0
                                  ? null
                                  : _sendCode,
                              child: Text(_resendSeconds > 0
                                  ? 'Kirim ulang ($_resendSeconds dtk)'
                                  : 'Kirim ulang kode'),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _changeEmail,
                              child: const Text('Ganti email'),
                            ),
                          ],
                        ),
                      ],
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
  _OwnerSection _selectedSection = _OwnerSection.dashboard;

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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final useDrawer = constraints.maxWidth < 900;
          return Scaffold(
            appBar: useDrawer
                ? AppBar(
                    title: Text(_selectedSection.label),
                    actions: [
                      IconButton(
                        tooltip: 'Muat ulang',
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  )
                : null,
            drawer: useDrawer
                ? Drawer(
                    child: Builder(
                      builder: (drawerContext) => _OwnerNavigation(
                        email: widget.email,
                        selected: _selectedSection,
                        onSelected: (section) {
                          setState(() => _selectedSection = section);
                          Navigator.of(drawerContext).pop();
                        },
                      ),
                    ),
                  )
                : null,
            body: Row(
              children: [
                if (!useDrawer)
                  SizedBox(
                    width: 250,
                    child: _OwnerNavigation(
                      email: widget.email,
                      selected: _selectedSection,
                      onSelected: (section) =>
                          setState(() => _selectedSection = section),
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
                        return _DashboardLoadError(onRetry: _reload);
                      }
                      final data = snapshot.data!;
                      if (data.cloudRequired) {
                        return _CloudEntitlementRequired(
                          data: data,
                          onRetry: _reload,
                        );
                      }
                      return switch (_selectedSection) {
                        _OwnerSection.dashboard => _OwnerDashboard(
                            data: data,
                            onRefresh: _reload,
                          ),
                        _OwnerSection.finance => _FinanceSummary(
                            data: data,
                            onRefresh: _reload,
                          ),
                        _OwnerSection.branches => _BranchList(
                            data: data,
                            onRefresh: _reload,
                          ),
                      };
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
}

enum _OwnerSection { dashboard, finance, branches }

extension on _OwnerSection {
  String get label => switch (this) {
        _OwnerSection.dashboard => 'Dashboard',
        _OwnerSection.finance => 'Laporan keuangan',
        _OwnerSection.branches => 'Cabang',
      };

  IconData get icon => switch (this) {
        _OwnerSection.dashboard => Icons.dashboard_rounded,
        _OwnerSection.finance => Icons.account_balance_wallet_outlined,
        _OwnerSection.branches => Icons.storefront_outlined,
      };
}

class _OwnerNavigation extends StatelessWidget {
  final String email;
  final _OwnerSection selected;
  final ValueChanged<_OwnerSection> onSelected;

  const _OwnerNavigation({
    required this.email,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppTheme.primaryDeep,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandHeader(dark: true),
                const SizedBox(height: 40),
                for (final section in _OwnerSection.values)
                  _MenuItem(
                    icon: section.icon,
                    label: section.label,
                    selected: selected == section,
                    onTap: () => onSelected(section),
                  ),
                const Spacer(),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: Supabase.instance.client.auth.signOut,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Keluar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: .9),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DashboardLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _DashboardLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) => _OwnerPageShell(
        child: _PortalMessageCard(
          icon: Icons.cloud_off_outlined,
          title: 'Data dashboard belum dapat dimuat',
          message:
              'Periksa koneksi internet lalu coba lagi. Jika kendala tetap '
              'terjadi, hubungi dukungan Sajia dan sertakan email owner Anda.',
          actionLabel: 'Coba lagi',
          onAction: onRetry,
        ),
      );
}

class _CloudEntitlementRequired extends StatelessWidget {
  final _OwnerDashboardData data;
  final VoidCallback onRetry;

  const _CloudEntitlementRequired({
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => _OwnerPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PortalMessageCard(
              icon: Icons.cloud_outlined,
              title: 'Paket Cloud diperlukan',
              message: 'Owner Portal menampilkan laporan hanya untuk cabang '
                  'dengan paket Cloud aktif. Aktifkan Cloud melalui menu '
                  'Pengaturan > Paket Sajia di aplikasi, lalu cek kembali di sini.',
              actionLabel: 'Cek ulang akses Cloud',
              onAction: onRetry,
            ),
            if (data.outlets.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Status paket cabang',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _OutletStatusList(outlets: data.outlets),
            ],
          ],
        ),
      );
}

class _PortalMessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PortalMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
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
                    child: Icon(icon, color: AppTheme.primary, size: 28),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      height: 1.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(actionLabel),
                  ),
                ],
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
  final bool cloudRequired;
  final List<_BranchData> branches;
  final List<_OwnerOutletData> outlets;

  const _OwnerDashboardData({
    required this.revenue,
    required this.cogs,
    required this.expenses,
    required this.transactions,
    required this.cloudRequired,
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
      cloudRequired: json['cloud_required'] == true,
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
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
        ),
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
                            Text('Periode bulan berjalan • cabang Cloud',
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
                    _MetricGrid(
                      metrics: [
                        _MetricData(
                          label: 'Omzet',
                          value: _rupiah(data.revenue),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.primary,
                        ),
                        _MetricData(
                          label: 'Transaksi',
                          value: '${data.transactions}',
                          icon: Icons.receipt_long_outlined,
                          color: AppTheme.info,
                        ),
                        _MetricData(
                          label: 'Laba kotor',
                          value: _rupiah(data.grossProfit),
                          icon: Icons.trending_up_rounded,
                          color: AppTheme.success,
                        ),
                        _MetricData(
                          label: 'Beban usaha',
                          value: _rupiah(data.expenses),
                          icon: Icons.remove_circle_outline_rounded,
                          color: AppTheme.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MetricGrid(
                      metrics: [
                        _MetricData(
                          label: 'Cabang terdaftar',
                          value: '${data.outlets.length}',
                          icon: Icons.storefront_outlined,
                          color: AppTheme.primary,
                        ),
                        _MetricData(
                          label: 'Cabang Cloud',
                          value: '${data.cloudOutletCount}',
                          icon: Icons.cloud_done_outlined,
                          color: AppTheme.success,
                        ),
                        _MetricData(
                          label: 'Cabang Pro',
                          value: '${data.proOutletCount}',
                          icon: Icons.workspace_premium_outlined,
                          color: AppTheme.gold,
                        ),
                        _MetricData(
                          label: 'Cabang Free',
                          value: '${data.outlets.length - data.proOutletCount}',
                          icon: Icons.sell_outlined,
                          color: AppTheme.warning,
                        ),
                      ],
                    ),
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

class _FinanceSummary extends StatelessWidget {
  final _OwnerDashboardData data;
  final VoidCallback onRefresh;

  const _FinanceSummary({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) => _OwnerPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: 'Laporan keuangan',
              subtitle: 'Ringkasan laba rugi bulan berjalan',
              onRefresh: onRefresh,
            ),
            const SizedBox(height: 26),
            _NetProfitCard(data: data),
            const SizedBox(height: 16),
            _MetricGrid(
              metrics: [
                _MetricData(
                  label: 'Omzet',
                  value: _rupiah(data.revenue),
                  icon: Icons.payments_outlined,
                  color: AppTheme.primary,
                ),
                _MetricData(
                  label: 'Harga pokok',
                  value: _rupiah(data.cogs),
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.warning,
                ),
                _MetricData(
                  label: 'Laba kotor',
                  value: _rupiah(data.grossProfit),
                  icon: Icons.trending_up_rounded,
                  color: AppTheme.success,
                ),
                _MetricData(
                  label: 'Beban usaha',
                  value: _rupiah(data.expenses),
                  icon: Icons.remove_circle_outline_rounded,
                  color: AppTheme.danger,
                ),
              ],
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Rincian laba rugi'),
            const SizedBox(height: 12),
            _FinanceBreakdownCard(data: data),
          ],
        ),
      );
}

class _BranchList extends StatelessWidget {
  final _OwnerDashboardData data;
  final VoidCallback onRefresh;

  const _BranchList({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) => _OwnerPageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: 'Cabang',
              subtitle: 'Status paket dan performa seluruh cabang',
              onRefresh: onRefresh,
            ),
            const SizedBox(height: 26),
            _MetricGrid(
              metrics: [
                _MetricData(
                  label: 'Cabang terdaftar',
                  value: '${data.outlets.length}',
                  icon: Icons.storefront_outlined,
                  color: AppTheme.primary,
                ),
                _MetricData(
                  label: 'Cabang Cloud',
                  value: '${data.cloudOutletCount}',
                  icon: Icons.cloud_done_outlined,
                  color: AppTheme.success,
                ),
                _MetricData(
                  label: 'Cabang Pro',
                  value: '${data.proOutletCount}',
                  icon: Icons.workspace_premium_outlined,
                  color: AppTheme.gold,
                ),
                _MetricData(
                  label: 'Cabang Free',
                  value: '${data.outlets.length - data.proOutletCount}',
                  icon: Icons.sell_outlined,
                  color: AppTheme.warning,
                ),
              ],
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Status paket cabang'),
            const SizedBox(height: 12),
            if (data.outlets.isEmpty)
              const _EmptyPortalCard(
                message: 'Belum ada cabang terhubung ke owner ini.',
              )
            else
              _OutletStatusList(outlets: data.outlets),
            const SizedBox(height: 30),
            const _SectionTitle('Performa bulan ini'),
            const SizedBox(height: 12),
            if (data.branches.isEmpty)
              const _EmptyPortalCard(
                message: 'Belum ada transaksi cabang pada periode ini.',
              )
            else
              _BranchPerformanceList(branches: data.branches),
          ],
        ),
      );
}

class _OwnerPageShell extends StatelessWidget {
  final Widget child;
  const _OwnerPageShell({required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppTheme.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600
                ? 16.0
                : constraints.maxWidth < 1000
                    ? 28.0
                    : 40.0;
            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: child,
                ),
              ),
            );
          },
        ),
      );
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRefresh;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 900)
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      );
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> metrics;
  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final columns = constraints.maxWidth >= 840
              ? 4
              : constraints.maxWidth >= 480
                  ? 2
                  : 1;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: _DashboardMetric(
                    label: metric.label,
                    value: metric.value,
                    icon: metric.icon,
                    color: metric.color,
                  ),
                ),
            ],
          );
        },
      );
}

class _FinanceBreakdownCard extends StatelessWidget {
  final _OwnerDashboardData data;
  const _FinanceBreakdownCard({required this.data});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _FinanceLine(label: 'Omzet', value: data.revenue),
              _FinanceLine(label: 'Harga pokok', value: -data.cogs),
              const Divider(height: 24),
              _FinanceLine(
                label: 'Laba kotor',
                value: data.grossProfit,
                emphasized: true,
              ),
              _FinanceLine(label: 'Beban usaha', value: -data.expenses),
              const Divider(height: 24),
              _FinanceLine(
                label: 'Laba bersih',
                value: data.netProfit,
                emphasized: true,
              ),
            ],
          ),
        ),
      );
}

class _FinanceLine extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasized;

  const _FinanceLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: emphasized ? null : AppTheme.textSecondary,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Flexible(
              child: Text(
                _rupiah(value),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
                  color: value < 0 ? AppTheme.danger : null,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EmptyPortalCard extends StatelessWidget {
  final String message;
  const _EmptyPortalCard({required this.message});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
}

class _OutletStatusList extends StatelessWidget {
  final List<_OwnerOutletData> outlets;
  const _OutletStatusList({required this.outlets});

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          children: [
            for (var index = 0; index < outlets.length; index++) ...[
              _OutletStatusRow(outlet: outlets[index]),
              if (index < outlets.length - 1)
                const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      );
}

class _BranchPerformanceList extends StatelessWidget {
  final List<_BranchData> branches;
  const _BranchPerformanceList({required this.branches});

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          children: [
            for (var index = 0; index < branches.length; index++) ...[
              _BranchRow(rank: index + 1, branch: branches[index]),
              if (index < branches.length - 1)
                const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      );
}

class _NetProfitCard extends StatelessWidget {
  final _OwnerDashboardData data;
  const _NetProfitCard({required this.data});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LABA BERSIH',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .75),
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                  const SizedBox(height: 8),
                  Text(
                    _rupiah(data.netProfit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: constraints.maxWidth < 380 ? 24 : 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Margin ${data.margin.toStringAsFixed(1)}% bulan ini',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .85)),
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 380) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.insights_rounded,
                    color: Colors.white, size: 30),
              ),
            ],
          ]),
        ),
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
            Icon(icon, color: color, size: AppTheme.iconDefault),
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final avatar = CircleAvatar(
            backgroundColor:
                rank == 1 ? AppTheme.goldLight : AppTheme.primaryLight,
            child: Text('$rank',
                style: TextStyle(
                    color: rank == 1 ? AppTheme.warning : AppTheme.primary,
                    fontWeight: FontWeight.w800)),
          );
          if (constraints.maxWidth < 560) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(branch.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                          '${branch.transactions} transaksi • ${_rupiah(branch.revenue)}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Laba ${_rupiah(branch.netProfit)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListTile(
            leading: avatar,
            title: Text(branch.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${branch.transactions} transaksi'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_rupiah(branch.revenue),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('Laba ${_rupiah(branch.netProfit)}',
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.success)),
              ],
            ),
          );
        },
      );
}

class _OutletStatusRow extends StatelessWidget {
  final _OwnerOutletData outlet;
  const _OutletStatusRow({required this.outlet});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final statusColor = outlet.isCloud
              ? AppTheme.success
              : outlet.isPro
                  ? AppTheme.gold
                  : AppTheme.warning;
          final avatar = CircleAvatar(
            backgroundColor:
                outlet.isCloud ? AppTheme.primaryLight : AppTheme.goldLight,
            child: Icon(
              outlet.isCloud
                  ? Icons.cloud_done_outlined
                  : outlet.isPro
                      ? Icons.workspace_premium_outlined
                      : Icons.sell_outlined,
              color: outlet.isCloud ? AppTheme.primary : AppTheme.warning,
              size: 20,
            ),
          );
          final status = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                outlet.planLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                ),
              ),
              if (outlet.cloudExpiry != null)
                Text(
                  'Cloud s/d ${DateFormat('d MMM y', 'id_ID').format(outlet.cloudExpiry!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(outlet.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          outlet.address ?? 'Alamat belum diisi',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerLeft, child: status),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListTile(
            leading: avatar,
            title: Text(outlet.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(outlet.address ?? 'Alamat belum diisi'),
            trailing: status,
          );
        },
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
  final bool selected;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: Colors.white.withValues(alpha: selected ? 1 : .78),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color:
                            Colors.white.withValues(alpha: selected ? 1 : .86),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import '../../core/backup_service.dart';
import '../../core/app_distribution.dart';
import '../settings/printer_settings.dart';
import '../../core/bluetooth_system.dart';
import '../../core/notification_service.dart';
import '../../core/onboarding_service.dart';
import '../../core/pro_subscription_service.dart';
import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../shared/polish_widgets.dart';
import 'pro_checkout_page.dart';

Future<User?> _findActiveUserUsingPin(
  AppDatabase db,
  String rawPin, {
  required Iterable<String> outletIds,
  String? excludeUserId,
}) async {
  final activeUsers = await db.sessionDao.getActiveUsersForOutlets(outletIds);
  for (final user in activeUsers) {
    if (excludeUserId != null && user.id == excludeUserId) continue;
    if (PinHasher.verify(rawPin, user.outletId, user.pin)) {
      return user;
    }
  }
  return null;
}

Future<List<User>> _loadVerifiedAccountUsers(
  AppDatabase db,
  String currentOutletId,
) async {
  final verifiedOutletIds =
      await OnboardingService().getVerifiedOwnerOutletIds();
  final scope = verifiedOutletIds.isNotEmpty
      ? verifiedOutletIds
      : currentOutletId.isEmpty || currentOutletId == 'default-outlet'
          ? const <String>{}
          : <String>{currentOutletId};
  return db.sessionDao.getActiveUsersForOutlets(scope);
}

String _nameInitial(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    _packageInfo = PackageInfo.fromPlatform();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cleanupPlaceholderOutlet();
    });
  }

  Future<void> _cleanupPlaceholderOutlet() async {
    final db = ref.read(databaseProvider);
    final outlets = await (db.select(db.outlets)
          ..orderBy([(outlet) => OrderingTerm.asc(outlet.name)]))
        .get();
    Outlet? placeholder;
    for (final outlet in outlets) {
      if (_isPlaceholderOutlet(outlet)) {
        placeholder = outlet;
        break;
      }
    }
    if (placeholder == null) return;
    final placeholderId = placeholder.id;

    final realOutlets =
        outlets.where((outlet) => !_isPlaceholderOutlet(outlet)).toList();
    if (realOutlets.isEmpty) return;

    final hasBusinessData = (await (db.select(db.users)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.categories)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.products)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.restaurantTables)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.orders)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.sessions)
                  ..where((row) => row.outletId.equals(placeholderId)))
                .get())
            .isNotEmpty ||
        (await (db.select(db.expenses)..where((row) => row.outletId.equals(placeholderId))).get()).isNotEmpty;
    if (hasBusinessData) return;

    if (ref.read(currentOutletIdProvider) == placeholderId) {
      await _setActiveOutlet(ref, realOutlets.first.id);
    }

    await (db.delete(db.userOutletAccesses)
          ..where((access) => access.outletId.equals(placeholderId)))
        .go();
    await (db.delete(db.outlets)
          ..where((outlet) => outlet.id.equals(placeholderId)))
        .go();
    ref.invalidate(currentOutletProvider);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final outlet = ref.watch(currentOutletProvider).value;
    final isPro = (outlet?.licenseKey ?? 'FREE').toUpperCase() == 'PRO';
    final isCloud = isPro &&
        outlet?.cloudExpiry != null &&
        outlet!.cloudExpiry!.isAfter(DateTime.now());
    final canManageOperations = user?.canManageOperations == true;
    final canSwitchOutlet =
        user?.isOwner == true || (user?.accessibleOutletIds.length ?? 0) > 1;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(16, 16, 16, pageBottomSafePadding(context)),
        children: [
          // Info user aktif
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppTheme.floatingShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _nameInitial(user?.name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? '-',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(
                      user?.roleLabel ?? '-',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const SajiaMark(
                    size: 38,
                    radius: 12,
                    showBadge: false,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (canManageOperations) ...[
            // Outlet Info
            const _SectionHeader('Informasi Outlet'),
            _SettingsCard(children: [
              if (canSwitchOutlet) ...[
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Cabang Aktif',
                  subtitle: outlet?.name ?? 'Pilih cabang yang sedang dikelola',
                  onTap: () => _openOutletSwitcher(context),
                ),
                _SettingsDivider(),
              ],
              _SettingsTile(
                icon: Icons.store_outlined,
                title: 'Edit Outlet Aktif',
                subtitle: 'Nama, alamat, dan nomor telepon struk',
                onTap: () => _openOutletForm(context),
              ),
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: 'Pengaturan Struk',
                subtitle: 'Header, footer, pajak, service charge',
                onTap: () => _openReceiptSettings(context),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // User Management (owner only)
          if (user?.isOwner == true) ...[
            const _SectionHeader('Manajemen Cabang'),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.storefront_outlined,
                title: 'Daftar Cabang',
                subtitle: 'Tambah, edit, dan pindah cabang aktif',
                onTap: () => _openOutletList(context),
              ),
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.add_business_outlined,
                title: 'Tambah Cabang',
                subtitle: 'Buat outlet baru untuk multi cabang',
                onTap: () => _openAddOutlet(context),
              ),
            ]),
            const SizedBox(height: 16),
            const _SectionHeader('Manajemen Staff'),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.people_outline,
                title: 'Daftar Staff',
                subtitle: 'Lihat & kelola akun kasir dan manager',
                onTap: () => _openUserList(context),
              ),
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.person_add_outlined,
                title: 'Tambah Staff',
                subtitle: 'Buat akun kasir atau manager baru',
                onTap: () => _openAddUser(context, ref),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          if (canManageOperations) ...[
            // Notifikasi Dapur
            const _SectionHeader('Dapur'),
            _KitchenNotifTile(),
            const SizedBox(height: 16),

            const _SectionHeader('Printer'),
            const PrinterSettingsCard(),
            const SizedBox(height: 16),
          ],

          // PIN saya
          const _SectionHeader('Keamanan'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.pin_outlined,
              title: 'Ganti PIN Saya',
              subtitle: 'Ubah PIN login kamu',
              onTap: () => _openChangePIN(context, ref),
            ),
          ]),
          const SizedBox(height: 16),

          //       _SettingsTile(
          // icon: Icons.restore_outlined,
          //  title: 'Restore Data',
          // subtitle: 'Restore dari backup terakhir di Documents',
          //  onTap: () => _confirmRestore(context, ref),
          //),

          // App info
          const _SectionHeader('Aplikasi'),
          _SettingsCard(children: [
            const _SettingsTile(
              icon: Icons.verified_outlined,
              title: AppBrand.name,
              subtitle: AppBrand.descriptor,
              onTap: null,
              trailing: Text('Brand',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            ),
            _SettingsDivider(),
            const _SettingsTile(
              icon: Icons.business_center_outlined,
              title: 'Made by Aijou Teknologi Digital',
              subtitle: 'Pengembang resmi aplikasi Sajia',
              onTap: null,
              trailing: Text('Developer',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: isCloud
                  ? Icons.cloud_done_outlined
                  : isPro
                      ? Icons.workspace_premium
                      : Icons.sell_outlined,
              title: 'Paket Sajia',
              subtitle: isCloud
                  ? 'Cloud aktif: backup online dan laporan lintas cabang.'
                  : isPro
                      ? 'Pro aktif: semua fitur aplikasi terbuka secara lokal.'
                      : 'Free aktif: 1 outlet dengan data lokal.',
              onTap: user?.isOwner == true
                  ? () => _openPlanActivation(context)
                  : null,
              trailing: Text(
                  isCloud
                      ? 'Cloud'
                      : isPro
                          ? 'Pro'
                          : 'Free',
                  style: TextStyle(
                    color: isCloud
                        ? AppTheme.success
                        : isPro
                            ? AppTheme.gold
                            : AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  )),
            ),
            _SettingsDivider(),
            FutureBuilder<PackageInfo>(
              future: _packageInfo,
              builder: (context, snapshot) {
                final version = snapshot.data?.version.trim();
                final displayVersion = version != null && version.isNotEmpty
                    ? version
                    : snapshot.hasError
                        ? 'Tidak tersedia'
                        : 'Memuat...';
                return _SettingsTile(
                  icon: Icons.info_outline,
                  title: 'Versi Aplikasi',
                  subtitle: displayVersion,
                  onTap: null,
                  trailing: Text(
                    displayVersion,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
            if (canManageOperations) ...[
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.storage_outlined,
                title: 'Sinkronisasi Data',
                subtitle: isCloud
                    ? 'Sync data ke cloud'
                    : 'Aktifkan Cloud untuk backup dan dashboard lintas cabang',
                onTap: () async {
                  if (!isCloud) {
                    _openPlanActivation(context);
                    return;
                  }

                  final sync = ref.read(syncServiceProvider);
                  await sync.syncAll();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Sinkronisasi selesai'),
                      backgroundColor: AppTheme.success,
                    ));
                  }
                },
              ),
            ],
          ]),
          const SizedBox(height: 16),
          if (canManageOperations) ...[
            // Backup & Restore
            const _SectionHeader('Data'),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.backup_outlined,
                title: 'Backup Data',
                subtitle: 'Export data ke file terenkripsi',
                onTap: () async {
                  final passphrase = await _askBackupPassword(context);
                  if (passphrase == null) return;
                  if (!context.mounted) return;

                  final db = ref.read(databaseProvider);
                  final outletId = ref.read(currentOutletIdProvider);
                  final result = await BackupService().createBackup(
                    db,
                    outletId,
                    passphrase: passphrase,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(result == BackupResult.success
                          ? 'Backup berhasil dibuat'
                          : 'Backup gagal: ${result.message}'),
                      backgroundColor: result == BackupResult.success
                          ? AppTheme.success
                          : AppTheme.danger,
                    ));
                  }
                },
              ),
              const SizedBox(height: 16),
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.restore_outlined,
                title: 'Restore Data',
                subtitle: 'Import data dari file backup terenkripsi',
                onTap: () => _confirmRestore(context, ref),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          const _SectionHeader('Akun'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Keluar',
              subtitle: 'Akhiri sesi kasir di perangkat ini',
              onTap: () => _confirmLogout(context, ref),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.danger),
            ),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar dari Sajia?'),
        content: const Text('Sesi kasir akan berakhir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(cartProvider.notifier).clear();
              ref.read(currentUserProvider.notifier).state = null;
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  void _openOutletForm(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _OutletFormSheet(),
    );
  }

  void _openOutletSwitcher(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _OutletSwitcherSheet(),
    );
  }

  void _openOutletList(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _OutletListSheet(),
    );
  }

  Future<void> _openAddOutlet(BuildContext ctx) async {
    if (!await _ensureCanCreateOutlet(ctx, ref)) return;
    if (!ctx.mounted) return;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _OutletFormSheet(createNew: true),
    );
  }

  void _openReceiptSettings(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReceiptSettingsSheet(),
    );
  }

  void _openUserList(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UserListSheet(),
    );
  }

  void _openAddUser(BuildContext ctx, WidgetRef ref) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UserFormSheet(),
    );
  }

  void _openChangePIN(BuildContext ctx, WidgetRef ref) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePINSheet(),
    );
  }

  void _openPlanActivation(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PlanActivationSheet(),
    );
  }
}

Future<bool> _ensureCanCreateOutlet(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final outlet = ref.read(currentOutletProvider).value;
  final outletCount =
      await db.select(db.outlets).get().then((rows) => rows.length);
  if (outletCount < 1) return true;

  if (outlet == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Data outlet belum siap. Coba lagi sebentar.'),
        backgroundColor: AppTheme.warning,
      ));
    }
    return false;
  }

  try {
    final status = await SajiaPlanService(ref.read(supabaseProvider))
        .refreshLocalPlan(database: db, outletId: outlet.id);
    ref.invalidate(currentOutletProvider);
    if (status.isPro) return true;
  } on SajiaPlanException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message),
        backgroundColor: AppTheme.warning,
      ));
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Gagal verifikasi lisensi Pro. Cek internet lalu coba lagi.'),
        backgroundColor: AppTheme.warning,
      ));
    }
    return false;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tambah cabang butuh Sajia Pro. Upgrade dulu ya.'),
      backgroundColor: AppTheme.warning,
    ));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PlanActivationSheet(),
    );
  }
  return false;
}

Future<String?> _askBackupPassword(BuildContext ctx) async {
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  var obscure = true;
  String? error;

  final result = await showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Password Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'File backup akan dienkripsi. Simpan password ini baik-baik, '
              'karena restore tidak bisa dilakukan tanpa password.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password backup',
                hintText: 'Minimal 8 karakter',
                errorText: error,
                suffixIcon: IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              obscureText: obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Ulangi password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = passCtrl.text.trim();
              if (password.length < 8) {
                setState(() => error = 'Password minimal 8 karakter');
                return;
              }
              if (password != confirmCtrl.text.trim()) {
                setState(() => error = 'Konfirmasi password tidak cocok');
                return;
              }
              Navigator.pop(dialogCtx, password);
            },
            child: const Text('Buat Backup'),
          ),
        ],
      ),
    ),
  );

  passCtrl.dispose();
  confirmCtrl.dispose();
  return result;
}

Future<String?> _askRestorePassword(BuildContext ctx) async {
  final passCtrl = TextEditingController();
  var obscure = true;
  String? error;

  final result = await showDialog<String>(
    context: ctx,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Password Restore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masukkan password backup. Kalau file backup lama masih JSON '
              'tanpa enkripsi, boleh dikosongkan.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password backup',
                hintText: 'Kosongkan untuk backup lama',
                errorText: error,
                suffixIcon: IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final password = passCtrl.text.trim();
              if (password.isNotEmpty && password.length < 8) {
                setState(() => error = 'Password minimal 8 karakter');
                return;
              }
              Navigator.pop(dialogCtx, password);
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    ),
  );

  passCtrl.dispose();
  return result;
}

void _confirmRestore(BuildContext ctx, WidgetRef ref) {
  showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      // title: const Text('Restore Data?'),
      content: const Text(
        'Data yang ada akan ditimpa dengan data dari file backup. '
        'Pastikan kamu punya backup terbaru sebelum melanjutkan.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final passphrase = await _askRestorePassword(ctx);
            if (passphrase == null) return;
            if (!ctx.mounted) return;

            final db = ref.read(databaseProvider);
            final result = await BackupService().restoreBackup(
              db,
              passphrase: passphrase,
            );
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(result == BackupResult.success
                    ? 'Data berhasil di-restore'
                    : result.message),
                backgroundColor: result == BackupResult.success
                    ? AppTheme.success
                    : AppTheme.danger,
              ));
            }
          },
          child:
              const Text('Restore', style: TextStyle(color: AppTheme.danger)),
        ),
      ],
    ),
  );
}

// ── OUTLET FORM ───────────────────────────────────────────────
class _PlanActivationSheet extends ConsumerStatefulWidget {
  const _PlanActivationSheet();

  @override
  ConsumerState<_PlanActivationSheet> createState() =>
      _PlanActivationSheetState();
}

class _PlanActivationSheetState extends ConsumerState<_PlanActivationSheet> {
  bool _isLoading = false;
  String? _error;

  Future<void> _startCheckout(String planCode) async {
    if (AppDistribution.isPlayStore) {
      setState(() {
        _error =
            'Upgrade dari versi Google Play dikelola lewat akun/lisensi bisnis. Jika lisensi sudah aktif, tekan Cek Status Lisensi.';
      });
      return;
    }

    final outlet = ref.read(currentOutletProvider).value;
    if (outlet == null) {
      setState(() => _error = 'Data outlet belum siap');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = SajiaPlanService(ref.read(supabaseProvider));
      final session = await service.createCheckout(
        outletId: outlet.id,
        outletName: outlet.name,
        planCode: planCode,
      );
      if (!mounted) return;

      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ProCheckoutPage(
            checkoutUrl: session.checkoutUrl,
            successUrl: session.successUrl,
          ),
        ),
      );
      if (completed == true) await _refreshPlan(showFeedback: true);
    } on SajiaPlanException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _paymentErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _paymentErrorMessage(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException') ||
        text.contains('timeout')) {
      return 'Koneksi ke payment service gagal. Cek internet lalu coba lagi.';
    }
    if (text.contains('401') || text.toLowerCase().contains('unauthorized')) {
      return 'Sesi owner belum valid. Login email owner dulu, lalu coba upgrade lagi.';
    }
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}...';
  }

  Future<void> _refreshPlan({bool showFeedback = false}) async {
    final outletId = ref.read(currentOutletIdProvider);
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status =
          await SajiaPlanService(ref.read(supabaseProvider)).refreshLocalPlan(
        database: ref.read(databaseProvider),
        outletId: outletId,
      );
      ref.invalidate(currentOutletProvider);

      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status.isCloud
            ? 'Sajia Cloud aktif. Terima kasih!'
            : status.isPro
                ? 'Sajia Pro aktif. Cloud bisa diaktifkan kapan saja.'
                : 'Pembayaran belum terkonfirmasi. Cek lagi sebentar.'),
        backgroundColor: status.isPro ? AppTheme.success : AppTheme.warning,
      ));
    } on SajiaPlanException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal mengecek status Pro');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outlet = ref.watch(currentOutletProvider).value;
    final license = (outlet?.licenseKey ?? 'FREE').toUpperCase();
    const isPlayStore = AppDistribution.isPlayStore;
    final isPro = license.startsWith('PRO');
    final isCloud = isPro &&
        outlet?.cloudExpiry != null &&
        outlet!.cloudExpiry!.isAfter(DateTime.now());

    return _BottomSheet(
      title: 'Paket Sajia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: isPro ? AppTheme.brandGradient : null,
              color: isPro ? null : AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPro ? Colors.transparent : AppTheme.subtleBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCloud
                      ? 'Sajia Cloud aktif'
                      : isPro
                          ? 'Sajia Pro aktif'
                          : 'Sajia Free aktif',
                  style: TextStyle(
                    color: isPro ? Colors.white : AppTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isCloud
                      ? 'Data outlet dibackup online dan siap dipakai untuk dashboard lintas cabang.'
                      : isPro
                          ? 'Lisensi aplikasi penuh aktif. Tambahkan Cloud untuk backup online dan dashboard cabang.'
                          : 'Satu outlet lokal dengan kasir, printer, produk unlimited, dan backup manual.',
                  style: TextStyle(
                    color: isPro
                        ? Colors.white.withValues(alpha: 0.78)
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PlanPoint('Free: satu outlet lokal dengan fitur kasir inti.'),
          if (isPlayStore) ...[
            const _PlanPoint(
                'Pro: fitur aplikasi lengkap dan multi outlet untuk akun bisnis berlisensi.'),
            const _PlanPoint(
                'Cloud: backup online, sinkronisasi, dan dashboard cabang untuk akun bisnis berlisensi.'),
            const SizedBox(height: 8),
            const Text(
              'Versi Google Play hanya menampilkan status lisensi. Jika lisensi sudah aktif, cek status untuk memperbarui akses.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ] else ...[
            const _PlanPoint(
                'Pro: Rp149.000 sekali bayar untuk fitur aplikasi lengkap dan multi outlet.'),
            const _PlanPoint(
                'Cloud: Rp10.000 per outlet/bulan untuk backup online, sync, dan dashboard cabang.'),
          ],
          const SizedBox(height: 18),
          if (_error != null) ...[
            Text(_error!,
                style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
          ],
          if (isPlayStore)
            _SaveButton(
              isSaving: _isLoading,
              onTap: () => _refreshPlan(showFeedback: true),
              label: 'Cek Status Lisensi',
            )
          else if (!isPro)
            _SaveButton(
              isSaving: _isLoading,
              onTap: () => _startCheckout('PRO_LIFETIME'),
              label: 'Beli Pro - Rp149.000',
            )
          else if (!isCloud)
            _SaveButton(
              isSaving: _isLoading,
              onTap: () => _startCheckout('CLOUD_MONTHLY'),
              label: 'Aktifkan Cloud - Rp10.000/bulan',
            )
          else
            _SaveButton(
              isSaving: _isLoading,
              onTap: () => _refreshPlan(showFeedback: true),
              label: 'Cek Status Cloud',
            ),
        ],
      ),
    );
  }
}

class _PlanPoint extends StatelessWidget {
  final String text;
  const _PlanPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 17, color: AppTheme.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _placeholderOutletId = 'default-outlet';
const _placeholderOutletName = 'Nama Kafe Saya';

bool _isPlaceholderOutlet(Outlet outlet) {
  return outlet.id == _placeholderOutletId &&
      outlet.name.trim().toLowerCase() == _placeholderOutletName.toLowerCase();
}

Future<List<Outlet>> _loadAccessibleOutlets(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final user = ref.read(currentUserProvider);
  final query = db.select(db.outlets);

  if (user == null) {
    query
        .where((outlet) => outlet.id.equals(ref.read(currentOutletIdProvider)));
  } else if (!user.canViewAllBranches) {
    final outletIds = user.accessibleOutletIds;
    if (outletIds.isEmpty) return [];
    query.where((outlet) => outlet.id.isIn(outletIds));
  }

  query.orderBy([(outlet) => OrderingTerm.asc(outlet.name)]);
  final outlets = await query.get();
  return outlets.where((outlet) => !_isPlaceholderOutlet(outlet)).toList();
}

Future<void> _setActiveOutlet(WidgetRef ref, String outletId) async {
  ref.read(currentOutletIdProvider.notifier).state = outletId;
  await OnboardingService().saveCurrentOutletId(outletId);
  ref.invalidate(currentOutletProvider);
}

class _OutletSwitcherSheet extends ConsumerWidget {
  const _OutletSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOutletId = ref.watch(currentOutletIdProvider);

    return _BottomSheet(
      title: 'Pilih Cabang Aktif',
      child: FutureBuilder<List<Outlet>>(
        future: _loadAccessibleOutlets(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const ErrorStateView(
              title: 'Cabang belum bisa dimuat',
              subtitle: 'Tutup panel ini lalu coba buka kembali.',
            );
          }
          final outlets = snapshot.data!;
          if (outlets.isEmpty) {
            return const EmptyStateView(
              icon: Icons.storefront_outlined,
              title: 'Belum ada cabang',
              subtitle: 'Owner bisa menambahkan cabang dari Manajemen Cabang.',
            );
          }

          return Column(
            children: [
              for (final outlet in outlets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: outlet.id == currentOutletId
                        ? AppTheme.primaryLight
                        : const Color(0xFFF3F4F6),
                    child: Icon(
                      Icons.storefront_outlined,
                      color: outlet.id == currentOutletId
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                  title: Text(outlet.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(outlet.address ?? 'Belum ada alamat'),
                  trailing: outlet.id == currentOutletId
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppTheme.success)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await _setActiveOutlet(ref, outlet.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OutletListSheet extends ConsumerWidget {
  const _OutletListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOutletId = ref.watch(currentOutletIdProvider);

    return _BottomSheet(
      title: 'Daftar Cabang',
      trailing: TextButton.icon(
        onPressed: () async {
          if (!await _ensureCanCreateOutlet(context, ref)) return;
          if (!context.mounted) return;
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
              builder: (_) => const _OutletFormSheet(createNew: true),
            );
          });
        },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Tambah'),
      ),
      child: FutureBuilder<List<Outlet>>(
        future: _loadAccessibleOutlets(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const ErrorStateView(
              title: 'Daftar cabang belum bisa dimuat',
              subtitle: 'Tutup panel ini lalu coba buka kembali.',
            );
          }
          final outlets = snapshot.data!;
          if (outlets.isEmpty) {
            return const EmptyStateView(
              icon: Icons.store_mall_directory_outlined,
              title: 'Belum ada cabang',
              subtitle: 'Tambahkan cabang pertama untuk mulai multi outlet.',
            );
          }

          return Column(
            children: [
              for (final outlet in outlets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryLight,
                    child: Text(
                      _nameInitial(outlet.name),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(outlet.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(outlet.address ?? 'Belum ada alamat'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (outlet.id == currentOutletId)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check_circle_rounded,
                              color: AppTheme.success, size: 20),
                        ),
                      IconButton(
                        tooltip: 'Edit cabang',
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        onPressed: () {
                          final navigatorContext =
                              Navigator.of(context, rootNavigator: true)
                                  .context;
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!navigatorContext.mounted) return;
                            showModalBottomSheet(
                              context: navigatorContext,
                              isScrollControlled: true,
                              useSafeArea: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => _OutletFormSheet(outlet: outlet),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  onTap: () async {
                    await _setActiveOutlet(ref, outlet.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OutletFormSheet extends ConsumerStatefulWidget {
  final Outlet? outlet;
  final bool createNew;

  const _OutletFormSheet({this.outlet, this.createNew = false});

  @override
  ConsumerState<_OutletFormSheet> createState() => _OutletFormSheetState();
}

class _OutletFormSheetState extends ConsumerState<_OutletFormSheet> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.outlet != null) {
      _nameCtrl.text = widget.outlet!.name;
      _addressCtrl.text = widget.outlet!.address ?? '';
      _phoneCtrl.text = widget.outlet!.phone ?? '';
    } else if (!widget.createNew) {
      _loadOutlet();
    }
  }

  Future<void> _loadOutlet() async {
    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final outlet = await (db.select(db.outlets)
          ..where((o) => o.id.equals(outletId)))
        .getSingleOrNull();
    if (outlet != null && mounted) {
      setState(() {
        _nameCtrl.text = outlet.name;
        _addressCtrl.text = outlet.address ?? '';
        _phoneCtrl.text = outlet.phone ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final String targetOutletId =
        widget.outlet?.id ?? ref.read(currentOutletIdProvider);

    if (widget.createNew) {
      if (!await _ensureCanCreateOutlet(context, ref)) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
      final newOutletId = const Uuid().v4();
      final address =
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim();
      final phone =
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();
      try {
        final created = await SajiaPlanService(ref.read(supabaseProvider))
            .createOwnerOutlet(
          id: newOutletId,
          name: _nameCtrl.text.trim(),
          address: address,
          phone: phone,
        );
        await db.into(db.outlets).insertOnConflictUpdate(
              OutletsCompanion.insert(
                id: created.id,
                name: created.name,
                address: Value(created.address),
                phone: Value(created.phone),
                licenseKey: created.isPro ? 'PRO' : 'FREE',
                licenseExpiry: const Value(null),
                cloudExpiry: Value(
                  created.isCloud ? created.cloudExpiresAt : null,
                ),
              ),
            );
        final onboarding = OnboardingService();
        final verifiedOutletIds = await onboarding.getVerifiedOwnerOutletIds();
        await onboarding.saveVerifiedOwnerOutletIds({
          ...verifiedOutletIds,
          created.id,
        });
        await _setActiveOutlet(ref, created.id);
        if (mounted) Navigator.pop(context);
      } on SajiaPlanException catch (error) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.message),
          backgroundColor: AppTheme.warning,
        ));
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal membuat cabang. Cek internet lalu coba lagi.'),
          backgroundColor: AppTheme.warning,
        ));
      }
      return;
    }

    await (db.update(db.outlets)..where((o) => o.id.equals(targetOutletId)))
        .write(
      OutletsCompanion(
        name: Value(_nameCtrl.text.trim()),
        address: Value(
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim()),
        phone: Value(
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
      ),
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      title: widget.createNew ? 'Tambah Cabang' : 'Informasi Outlet',
      child: Column(
        children: [
          _FormField('Nama Outlet *', _nameCtrl, 'Contoh: Sajia Coffee Braga'),
          const SizedBox(height: 12),
          _FormField('Alamat', _addressCtrl, 'Alamat lengkap outlet'),
          const SizedBox(height: 12),
          _FormField('No. Telepon', _phoneCtrl, '08xxxxxxxxxx',
              type: TextInputType.phone),
          const SizedBox(height: 24),
          _SaveButton(isSaving: _isSaving, onTap: _save),
        ],
      ),
    );
  }
}

// ── RECEIPT SETTINGS ──────────────────────────────────────────
class _ReceiptSettingsSheet extends ConsumerStatefulWidget {
  const _ReceiptSettingsSheet();

  @override
  ConsumerState<_ReceiptSettingsSheet> createState() =>
      _ReceiptSettingsSheetState();
}

class _ReceiptSettingsSheetState extends ConsumerState<_ReceiptSettingsSheet> {
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');
  final _serviceCtrl = TextEditingController(text: '0');
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final outlet = await (db.select(db.outlets)
          ..where((o) => o.id.equals(outletId)))
        .getSingleOrNull();
    if (outlet != null && mounted) {
      setState(() {
        _headerCtrl.text = outlet.receiptHeader ?? '';
        _footerCtrl.text = outlet.receiptFooter ?? '';
        _taxCtrl.text = outlet.taxPercent;
        _serviceCtrl.text = outlet.serviceChargePercent;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);

    await (db.update(db.outlets)..where((o) => o.id.equals(outletId))).write(
      OutletsCompanion(
        receiptHeader: Value(
            _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text.trim()),
        receiptFooter: Value(
            _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text.trim()),
        taxPercent:
            Value(_taxCtrl.text.trim().isEmpty ? '0' : _taxCtrl.text.trim()),
        serviceChargePercent: Value(
            _serviceCtrl.text.trim().isEmpty ? '0' : _serviceCtrl.text.trim()),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _taxCtrl.dispose();
    _serviceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outlet = ref.watch(currentOutletProvider).value;

    return _BottomSheet(
      title: 'Pengaturan Struk',
      child: Column(
        children: [
          _FormField('Header Struk', _headerCtrl,
              'Contoh: Jl. Merdeka No. 1\nTelp: 08xxx',
              maxLines: 2),
          const SizedBox(height: 12),
          _FormField('Footer Struk', _footerCtrl,
              'Contoh: Terima kasih sudah berkunjung!',
              maxLines: 2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _FormField('Pajak (%)', _taxCtrl, '0',
                      type: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: _FormField('Service Charge (%)', _serviceCtrl, '0',
                      type: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: Listenable.merge([
              _headerCtrl,
              _footerCtrl,
              _taxCtrl,
              _serviceCtrl,
            ]),
            builder: (context, _) => _ReceiptPreviewCard(
              outletName: outlet?.name ?? 'Sajia',
              address: outlet?.address,
              phone: outlet?.phone,
              header: _headerCtrl.text,
              footer: _footerCtrl.text,
              taxPercent: _taxCtrl.text,
              servicePercent: _serviceCtrl.text,
            ),
          ),
          const SizedBox(height: 24),
          _SaveButton(isSaving: _isSaving, onTap: _save),
        ],
      ),
    );
  }
}

class _ReceiptPreviewCard extends StatelessWidget {
  final String outletName;
  final String? address;
  final String? phone;
  final String header;
  final String footer;
  final String taxPercent;
  final String servicePercent;

  const _ReceiptPreviewCard({
    required this.outletName,
    required this.address,
    required this.phone,
    required this.header,
    required this.footer,
    required this.taxPercent,
    required this.servicePercent,
  });

  double get _tax => double.tryParse(taxPercent.replaceAll(',', '.')) ?? 0;
  double get _service =>
      double.tryParse(servicePercent.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    const subtotal = 48000.0;
    final taxAmount = subtotal * _tax / 100;
    final serviceAmount = subtotal * _service / 100;
    final total = subtotal + taxAmount + serviceAmount;
    final paid = total <= 50000 ? 50000.0 : total;
    final change = paid - total;
    final headerLines = header
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final footerText = footer.trim().isEmpty
        ? 'Terima kasih sudah berkunjung!'
        : footer.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'Preview Struk',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.35,
                color: AppTheme.textPrimary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    outletName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if ((address ?? '').trim().isNotEmpty)
                    Text(address!.trim(), textAlign: TextAlign.center),
                  if ((phone ?? '').trim().isNotEmpty)
                    Text('Telp: ${phone!.trim()}', textAlign: TextAlign.center),
                  if (headerLines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final line in headerLines)
                      Text(line, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 8),
                  const Text('------------------------------'),
                  const Text('INV-0001        01/07/2026'),
                  const Text('Kasir: Owner'),
                  const Text('------------------------------'),
                  const _ReceiptPreviewRow('Kopi Susu x1', 'Rp 18.000'),
                  const _ReceiptPreviewRow('Nasi Goreng x1', 'Rp 30.000'),
                  const Text('------------------------------'),
                  _ReceiptPreviewRow('Subtotal', subtotal.toRupiah),
                  if (_tax > 0)
                    _ReceiptPreviewRow(
                        'Pajak ${_tax.toStringAsFixed(_tax % 1 == 0 ? 0 : 1)}%',
                        taxAmount.toRupiah),
                  if (_service > 0)
                    _ReceiptPreviewRow(
                        'Service ${_service.toStringAsFixed(_service % 1 == 0 ? 0 : 1)}%',
                        serviceAmount.toRupiah),
                  _ReceiptPreviewRow(
                    'TOTAL',
                    total.toRupiah,
                    isStrong: true,
                  ),
                  const Text('------------------------------'),
                  _ReceiptPreviewRow('Bayar', paid.toRupiah),
                  _ReceiptPreviewRow('Kembali', change.toRupiah),
                  const SizedBox(height: 8),
                  Text(footerText, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptPreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _ReceiptPreviewRow(this.label, this.value, {this.isStrong = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: isStrong ? FontWeight.w800 : null);
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

String _roleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'manager' => 'Manager',
      _ => 'Kasir',
    };

Color _roleColor(String role) => switch (role) {
      'owner' => AppTheme.primary,
      'manager' => AppTheme.warning,
      _ => AppTheme.success,
    };

// ── USER LIST ─────────────────────────────────────────────────
class _UserListSheet extends ConsumerWidget {
  const _UserListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final currentOutletId = ref.watch(currentOutletIdProvider);

    return _BottomSheet(
      title: 'Daftar Staff',
      child: FutureBuilder<List<User>>(
        future: _loadVerifiedAccountUsers(db, currentOutletId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const ErrorStateView(
              title: 'Daftar staff belum bisa dimuat',
              subtitle: 'Tutup panel ini lalu coba buka kembali.',
            );
          }

          final users = snapshot.data!;
          if (users.isEmpty) {
            return const EmptyStateView(
              icon: Icons.people_outline_rounded,
              title: 'Belum ada staff',
              subtitle: 'Tambahkan kasir atau manager untuk outlet ini.',
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _roleColor(u.role).withValues(alpha: 0.1),
                  child: Text(
                    _nameInitial(u.name),
                    style: TextStyle(
                      color: _roleColor(u.role),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(u.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _roleLabel(u.role),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: const Color(0xFF6B7280),
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
                        builder: (_) => _UserFormSheet(user: u),
                      );
                    });
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── USER FORM ─────────────────────────────────────────────────
class _OutletAccessSelector extends ConsumerWidget {
  final String role;
  final Set<String> selectedOutletIds;
  final ValueChanged<String> onToggle;

  const _OutletAccessSelector({
    required this.role,
    required this.selectedOutletIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (role == 'owner') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.subtleBorder),
        ),
        child: const Text(
          'Owner otomatis punya akses ke semua cabang.',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      );
    }

    return FutureBuilder<List<Outlet>>(
      future: _loadAccessibleOutlets(ref),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 52,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const ErrorStateView(
            title: 'Akses cabang belum bisa dimuat',
            subtitle: 'Tutup panel staff lalu coba lagi.',
          );
        }
        final outlets = snapshot.data!;
        if (outlets.isEmpty) {
          return const EmptyStateView(
            icon: Icons.storefront_outlined,
            title: 'Belum ada cabang',
            subtitle: 'Tambahkan cabang dulu sebelum membuat staff.',
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            children: [
              for (final outlet in outlets)
                CheckboxListTile(
                  value: selectedOutletIds.contains(outlet.id),
                  onChanged: (_) => onToggle(outlet.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(outlet.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    role == 'cashier'
                        ? 'Kasir hanya boleh 1 cabang'
                        : outlet.address ?? 'Manager bisa handle cabang ini',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UserFormSheet extends ConsumerStatefulWidget {
  final User? user;
  const _UserFormSheet({this.user});

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  static const _pinLength = 6;
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  String _role = 'cashier';
  Set<String> _selectedOutletIds = {};
  bool _isSaving = false;
  bool _obscurePin = true;
  String? _pinError;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      _nameCtrl.text = widget.user!.name;
      _role = widget.user!.role;
      _loadUserOutletAccess();
    } else {
      _selectedOutletIds = {ref.read(currentOutletIdProvider)};
    }
  }

  Future<void> _loadUserOutletAccess() async {
    final outletIds = await ref
        .read(databaseProvider)
        .sessionDao
        .getUserOutletIds(widget.user!.id);
    if (!mounted) return;
    setState(() {
      _selectedOutletIds =
          outletIds.isEmpty ? {widget.user!.outletId} : outletIds.toSet();
    });
  }

  void _setRole(String role) {
    setState(() {
      _role = role;
      if (role == 'owner') {
        _selectedOutletIds = {};
      } else if (role == 'cashier' && _selectedOutletIds.length > 1) {
        _selectedOutletIds = {_selectedOutletIds.first};
      } else if (_selectedOutletIds.isEmpty) {
        _selectedOutletIds = {ref.read(currentOutletIdProvider)};
      }
    });
  }

  void _toggleOutlet(String outletId) {
    setState(() {
      if (_role == 'cashier') {
        _selectedOutletIds = {outletId};
        return;
      }
      if (_selectedOutletIds.contains(outletId)) {
        if (_selectedOutletIds.length > 1) {
          _selectedOutletIds.remove(outletId);
        }
      } else {
        _selectedOutletIds.add(outletId);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;

    // Validasi PIN
    if (!_isEdit || _pinCtrl.text.isNotEmpty) {
      if (_pinCtrl.text.length != _pinLength) {
        setState(() => _pinError = 'PIN harus 6 digit');
        return;
      }
      if (_pinCtrl.text != _pinConfirmCtrl.text) {
        setState(() => _pinError = 'PIN tidak cocok');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _pinError = null;
    });

    final db = ref.read(databaseProvider);
    final outletId = ref.read(currentOutletIdProvider);
    final id = widget.user?.id ?? const Uuid().v4();
    final assignedOutletIds =
        _role == 'owner' ? <String>[] : _selectedOutletIds.toList();

    if (_role != 'owner' && assignedOutletIds.isEmpty) {
      setState(() {
        _pinError = 'Pilih minimal 1 cabang';
        _isSaving = false;
      });
      return;
    }
    final homeOutletId = widget.user?.outletId ??
        (assignedOutletIds.isEmpty ? outletId : assignedOutletIds.first);

    String pin = widget.user?.pin ?? '';
    if (_pinCtrl.text.isNotEmpty) {
      final verifiedOutletIds =
          await OnboardingService().getVerifiedOwnerOutletIds();
      final accountOutletIds =
          verifiedOutletIds.isEmpty ? <String>{outletId} : verifiedOutletIds;
      final existingPinOwner = await _findActiveUserUsingPin(
        db,
        _pinCtrl.text,
        outletIds: accountOutletIds,
        excludeUserId: widget.user?.id,
      );
      if (existingPinOwner != null) {
        if (!mounted) return;
        setState(() {
          _pinError =
              'PIN sudah dipakai oleh ${existingPinOwner.name}. Gunakan PIN lain.';
          _isSaving = false;
        });
        return;
      }
      pin = PinHasher.hash(_pinCtrl.text, homeOutletId);
    }

    await db.sessionDao.upsertUser(UsersCompanion(
      id: Value(id),
      outletId: Value(homeOutletId),
      name: Value(_nameCtrl.text.trim()),
      pin: Value(pin),
      role: Value(_role),
      isActive: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
    await db.sessionDao.replaceUserOutletAccess(id, assignedOutletIds);

    if (mounted) Navigator.pop(context);
  }

  Future<void> _deactivate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nonaktifkan staff?'),
        content: Text('${widget.user!.name} tidak bisa login lagi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.sessionDao.deactivateUser(widget.user!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      title: _isEdit ? 'Edit Staff' : 'Tambah Staff',
      trailing: _isEdit
          ? TextButton(
              onPressed: _deactivate,
              child: const Text('Nonaktifkan',
                  style: TextStyle(color: AppTheme.danger, fontSize: 12)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FormField('Nama *', _nameCtrl, 'Nama lengkap staff'),
          const SizedBox(height: 12),

          // Role
          const Text('Role',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
          const SizedBox(height: 8),
          Row(
            children: [
              _RoleChip(
                label: 'Kasir',
                icon: Icons.point_of_sale_outlined,
                selected: _role == 'cashier',
                onTap: () => _setRole('cashier'),
              ),
              const SizedBox(width: 10),
              _RoleChip(
                label: 'Manager',
                icon: Icons.supervisor_account_outlined,
                selected: _role == 'manager',
                onTap: () => _setRole('manager'),
              ),
              const SizedBox(width: 10),
              _RoleChip(
                label: 'Owner',
                icon: Icons.admin_panel_settings_outlined,
                selected: _role == 'owner',
                onTap: () => _setRole('owner'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Text('Akses Cabang',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
          const SizedBox(height: 8),
          _OutletAccessSelector(
            role: _role,
            selectedOutletIds: _selectedOutletIds,
            onToggle: _toggleOutlet,
          ),
          const SizedBox(height: 12),

          // PIN
          Text(_isEdit ? 'PIN Baru (kosongkan jika tidak ganti)' : 'PIN *',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            obscureText: _obscurePin,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDeco('6 digit angka').copyWith(
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(_obscurePin
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pinConfirmCtrl,
            keyboardType: TextInputType.number,
            obscureText: _obscurePin,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDeco('Konfirmasi PIN').copyWith(
              counterText: '',
              errorText: _pinError,
            ),
          ),
          const SizedBox(height: 24),
          _SaveButton(
            isSaving: _isSaving,
            onTap: _save,
            label: _isEdit ? 'Simpan' : 'Tambah Staff',
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
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
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.danger)),
      );
}

// ── CHANGE PIN SHEET ──────────────────────────────────────────
class _ChangePINSheet extends ConsumerStatefulWidget {
  const _ChangePINSheet();

  @override
  ConsumerState<_ChangePINSheet> createState() => _ChangePINSheetState();
}

class _ChangePINSheetState extends ConsumerState<_ChangePINSheet> {
  static const _pinLength = 6;
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _isSaving = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);

    if (_oldPinCtrl.text.length != _pinLength) {
      setState(() => _error = 'PIN lama harus 6 digit');
      return;
    }
    if (_newPinCtrl.text.length != _pinLength) {
      setState(() => _error = 'PIN baru harus 6 digit');
      return;
    }
    if (_newPinCtrl.text != _confirmPinCtrl.text) {
      setState(() => _error = 'PIN baru tidak cocok');
      return;
    }

    setState(() => _isSaving = true);

    final db = ref.read(databaseProvider);
    final user = ref.read(currentUserProvider)!;

    // Verifikasi PIN lama milik user aktif.
    final dbUser = await db.sessionDao.getActiveUserById(user.id);

    if (dbUser == null ||
        !PinHasher.verify(_oldPinCtrl.text, dbUser.outletId, dbUser.pin)) {
      setState(() {
        _error = 'PIN lama salah';
        _isSaving = false;
      });
      return;
    }

    final verifiedOutletIds =
        await OnboardingService().getVerifiedOwnerOutletIds();
    final accountOutletIds = verifiedOutletIds.isEmpty
        ? <String>{dbUser.outletId}
        : verifiedOutletIds;
    final existingPinOwner = await _findActiveUserUsingPin(
      db,
      _newPinCtrl.text,
      outletIds: accountOutletIds,
      excludeUserId: dbUser.id,
    );
    if (existingPinOwner != null) {
      if (!mounted) return;
      setState(() {
        _error =
            'PIN baru sudah dipakai oleh ${existingPinOwner.name}. Gunakan PIN lain.';
        _isSaving = false;
      });
      return;
    }

    // Update PIN
    final newHashed = PinHasher.hash(_newPinCtrl.text, dbUser.outletId);
    await db.sessionDao.upsertUser(UsersCompanion(
      id: Value(user.id),
      outletId: Value(dbUser.outletId),
      name: Value(user.name),
      pin: Value(newHashed),
      role: Value(user.role),
      updatedAt: Value(DateTime.now()),
    ));

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('PIN berhasil diubah'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      title: 'Ganti PIN',
      child: Column(
        children: [
          _PinField('PIN Lama', _oldPinCtrl, _obscure,
              () => setState(() => _obscure = !_obscure)),
          const SizedBox(height: 12),
          _PinField('PIN Baru', _newPinCtrl, _obscure,
              () => setState(() => _obscure = !_obscure)),
          const SizedBox(height: 12),
          _PinField('Konfirmasi PIN Baru', _confirmPinCtrl, _obscure,
              () => setState(() => _obscure = !_obscure),
              errorText: _error),
          const SizedBox(height: 24),
          _SaveButton(isSaving: _isSaving, onTap: _save, label: 'Simpan PIN'),
        ],
      ),
    );
  }
}

// ── REUSABLE WIDGETS ──────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF9CA3AF))),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.subtleBorder),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(children: children),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 18),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB))
                : null),
      );
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 56);
}

class _BottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _BottomSheet({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomSafeSpace = bottomSheetSafePadding(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
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
      padding: EdgeInsets.only(
        bottom: bottomSafeSpace,
        top: 8,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final TextInputType type;
  final int maxLines;

  const _FormField(this.label, this.ctrl, this.hint,
      {this.type = TextInputType.text, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
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
        ],
      );
}

class _PinField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool obscure;
  final VoidCallback onToggle;
  final String? errorText;

  const _PinField(this.label, this.ctrl, this.obscure, this.onToggle,
      {this.errorText});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            obscureText: obscure,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              errorText: errorText,
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: IconButton(
                icon: Icon(obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: onToggle,
              ),
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
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.danger)),
            ),
          ),
        ],
      );
}

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onTap;
  final String label;

  const _SaveButton({
    required this.isSaving,
    required this.onTap,
    this.label = 'Simpan',
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: isSaving ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryLight : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.borderColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color:
                        selected ? AppTheme.primary : const Color(0xFF9CA3AF),
                    size: 22),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          selected ? AppTheme.primary : const Color(0xFF6B7280),
                    )),
              ],
            ),
          ),
        ),
      );
}

// ── KITCHEN NOTIF TILE ────────────────────────────────────────
class _KitchenNotifTile extends StatefulWidget {
  @override
  State<_KitchenNotifTile> createState() => _KitchenNotifTileState();
}

class _KitchenNotifTileState extends State<_KitchenNotifTile> {
  bool _enabled = false;
  bool _loading = true;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await NotificationService.isKitchenNotifEnabled();
    final deviceName = await NotificationService.getKitchenDeviceName();
    if (mounted) {
      setState(() {
        _enabled = val;
        _deviceName = deviceName;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool val) async {
    if (val) {
      final allowed = await BluetoothSystem.requestNotificationPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Izinkan notifikasi supaya order dapur bisa muncul'),
          backgroundColor: AppTheme.danger,
          duration: Duration(seconds: 2),
        ));
        return;
      }
    }

    await NotificationService.setKitchenNotif(val);
    setState(() => _enabled = val);

    if (val && mounted) {
      await _selectKitchenDevice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Notifikasi dapur aktif'),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _selectKitchenDevice() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BluetoothPickerSheet(
        onSelected: (device) async {
          await NotificationService.setKitchenDevice(
            name: device.name,
            address: device.address,
          );
          if (mounted) setState(() => _deviceName = device.name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(children: [
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.kitchen_outlined,
              color: AppTheme.primary, size: 18),
        ),
        title: const Text('Notifikasi Dapur',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(
          _enabled
              ? 'Aktif — notif muncul saat order masuk'
              : 'Nonaktif — tap untuk mengaktifkan',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
        trailing: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Switch(
                value: _enabled,
                onChanged: _toggle,
                activeThumbColor: AppTheme.success,
              ),
      ),
      if (_enabled) ...[
        _SettingsDivider(),
        ListTile(
          onTap: _selectKitchenDevice,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bluetooth_searching,
                color: AppTheme.primary, size: 18),
          ),
          title: const Text('Perangkat Dapur',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            _deviceName != null
                ? 'Terkoneksi ke $_deviceName untuk notif dapur'
                : 'Tap untuk mencari printer/perangkat dapur',
            style: TextStyle(
              fontSize: 11,
              color: _deviceName != null
                  ? AppTheme.success
                  : const Color(0xFF9CA3AF),
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB)),
        ),
      ],
    ]);
  }
}

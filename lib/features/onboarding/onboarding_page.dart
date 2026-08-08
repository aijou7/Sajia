import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/providers.dart';
import '../../core/app_distribution.dart';
import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/onboarding_service.dart';
import '../../data/local/app_database.dart';

enum _Step { welcome, email, otp, outlet, pin }

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with TickerProviderStateMixin {
  _Step _step = _Step.welcome;
  bool _isLoading = false;

  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _emailError;
  bool _isDeviceRecovery = false;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;

  static const _pinLength = 6;
  String _pin = '';
  String _confirmPin = '';
  bool _settingConfirm = false;
  String? _pinError;

  late final AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _slideCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startOtpCooldown(Duration duration) {
    _otpCooldownTimer?.cancel();
    final seconds = duration.inSeconds.clamp(1, 3600);
    setState(() => _otpCooldownSeconds = seconds);
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _otpCooldownSeconds = 0);
      } else {
        setState(() => _otpCooldownSeconds--);
      }
    });
  }

  void _goTo(_Step next) {
    _slideCtrl.reset();
    setState(() => _step = next);
    _slideCtrl.forward();
  }

  Future<void> _sendOtp() async {
    if (_isLoading) return;
    final service = OnboardingService();
    final email = service.normalizeEmail(_emailCtrl.text);
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _emailError = 'Masukkan alamat email yang valid.');
      return;
    }
    setState(() {
      _isLoading = true;
      _emailError = null;
      _emailCtrl.text = email;
      _otpCtrl.clear();
    });
    final result =
        await service.sendOtp(email, shouldCreateUser: !_isDeviceRecovery);
    if (!mounted) return;
    setState(() => _isLoading = false);
    switch (result) {
      case OtpResult.sent:
        _startOtpCooldown(OnboardingService.otpCooldown);
        if (_step != _Step.otp) {
          _goTo(_Step.otp);
        } else {
          _snack('Kode OTP baru sudah dikirim.', success: true);
        }
      case OtpResult.cooldown:
        final retry = service.lastOtpRetryAfter ??
            await service.otpCooldownRemaining(email);
        if (!mounted) return;
        _startOtpCooldown(retry);
        setState(() => _emailError =
            'Tunggu ${retry.inSeconds.clamp(1, 3600)} detik sebelum kirim ulang.');
      case OtpResult.rateLimited:
        final retry =
            service.lastOtpRetryAfter ?? OnboardingService.otpCooldown;
        _startOtpCooldown(retry);
        setState(() => _emailError =
            'Batas pengiriman tercapai. Coba lagi dalam ${retry.inSeconds.clamp(1, 3600)} detik.');
      case OtpResult.accountNotFound:
        setState(() => _emailError =
            'Email ini belum memiliki akun Sajia. Pilih Daftar bisnis baru.');
      case OtpResult.networkUnavailable:
        setState(() => _emailError =
            'Tidak dapat terhubung. Periksa internet lalu coba lagi.');
      case OtpResult.failed:
        setState(() => _emailError =
            'Kode OTP belum dapat dikirim. Coba lagi atau hubungi support jika berulang.');
    }
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return;
    if (_otpCtrl.text.trim().length != 6) {
      setState(() => _emailError = 'Masukkan 6 digit kode OTP.');
      return;
    }
    setState(() {
      _isLoading = true;
      _emailError = null;
    });
    final service = OnboardingService();
    final result = await service.verifyOtp(
      service.normalizeEmail(_emailCtrl.text),
      _otpCtrl.text,
    );
    if (!mounted) return;
    if (result == OtpVerifyResult.success) {
      await _continueAfterVerifiedEmail();
    } else {
      setState(() {
        _isLoading = false;
        _emailError = switch (result) {
          OtpVerifyResult.expired =>
            'Kode OTP sudah kedaluwarsa atau sudah diganti. Kirim ulang kode.',
          OtpVerifyResult.failed =>
            'Verifikasi OTP gagal. Periksa koneksi lalu coba lagi.',
          OtpVerifyResult.networkUnavailable =>
            'Tidak dapat terhubung. Periksa internet lalu coba lagi.',
          OtpVerifyResult.rateLimited =>
            'Terlalu banyak percobaan verifikasi. Tunggu sebentar lalu coba lagi.',
          _ => 'Kode OTP tidak valid. Pastikan memakai kode terbaru.',
        };
      });
    }
  }

  Future<void> _continueAfterVerifiedEmail() async {
    try {
      final outlets = await OnboardingService().getAuthenticatedOwnerOutlets();
      if (!mounted) return;
      if (outlets.isNotEmpty) {
        await _restoreExistingAccount(outlets: outlets);
        return;
      }
      if (_isDeviceRecovery) {
        setState(() {
          _isLoading = false;
          _emailError =
              'Email terverifikasi, tetapi belum terhubung ke outlet Sajia. Kembali lalu pilih Daftar bisnis baru.';
        });
        return;
      }
      setState(() => _isLoading = false);
      _goTo(_Step.outlet);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailError =
            'Akun sudah terverifikasi, tetapi data outlet belum dapat diperiksa. Periksa internet lalu coba lagi.';
      });
    }
  }

  Future<void> _restoreExistingAccount({
    List<Map<String, dynamic>>? outlets,
  }) async {
    try {
      final service = OnboardingService();
      final ownerOutlets =
          outlets ?? await service.getAuthenticatedOwnerOutlets();
      if (ownerOutlets.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _emailError =
              'Email ini belum terhubung ke outlet Sajia. Gunakan Daftar bisnis baru.';
        });
        return;
      }

      final outletId = ownerOutlets.first['id'] as String?;
      if (outletId == null || outletId.isEmpty) {
        throw StateError('ID outlet akun tidak valid');
      }

      final restored =
          await ref.read(syncServiceProvider).pullAllForLogin(outletId);
      if (!restored) {
        throw StateError('Koneksi ke penyimpanan akun gagal');
      }

      final db = ref.read(databaseProvider);
      final users = await db.sessionDao.getActiveUsers();
      final restoredOutletIds = ownerOutlets
          .map((outlet) => outlet['id'] as String?)
          .whereType<String>()
          .toSet();
      final hasRestoredOwner = users.any(
        (user) =>
            user.role == 'owner' && restoredOutletIds.contains(user.outletId),
      );

      if (!hasRestoredOwner) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _emailError =
              'PIN akun belum tersimpan di cloud. Buka Sajia di perangkat lama, sambungkan internet, lalu tunggu sinkronisasi sebelum mencoba lagi.';
        });
        return;
      }

      await service.saveCurrentOutletId(outletId);
      ref.read(currentOutletIdProvider.notifier).state = outletId;
      await service.markSetupDone();
      ref.invalidate(isSetupDoneProvider);

      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailError =
            'Data akun belum dapat dipulihkan. Periksa internet lalu coba lagi.';
      });
    }
  }

  // PIN ───────────────────────────────────────
  void _onPinDigit(String digit) {
    setState(() {
      _pinError = null;
      if (!_settingConfirm) {
        if (_pin.length < _pinLength) _pin += digit;
        if (_pin.length == _pinLength) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) setState(() => _settingConfirm = true);
          });
        }
      } else {
        if (_confirmPin.length < _pinLength) _confirmPin += digit;
        if (_confirmPin.length == _pinLength) _checkPins();
      }
    });
  }

  void _onPinDelete() {
    setState(() {
      _pinError = null;
      if (!_settingConfirm) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      }
    });
  }

  void _checkPins() {
    if (_pin == _confirmPin) {
      _finishSetup();
    } else {
      setState(() {
        _pinError = 'PIN tidak cocok. Coba lagi.';
        _confirmPin = '';
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _pin = '';
            _settingConfirm = false;
            _pinError = null;
          });
        }
      });
    }
  }

  // ── FINISH SETUP ──────────────────────────────
  Future<void> _finishSetup() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      const uuid = Uuid();

      final outletId = uuid.v4();
      final hashedPin = PinHasher.hash(_pin, outletId);
      final ownerId = uuid.v4();

      await db.into(db.outlets).insertOnConflictUpdate(OutletsCompanion.insert(
            id: outletId,
            name: _nameCtrl.text.trim(),
            address: Value(_addressCtrl.text.trim().isEmpty
                ? null
                : _addressCtrl.text.trim()),
            phone: Value(
                _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
            // Plan entitlements are server-owned. Never trust restored/local
            // backup data for Pro/Cloud because JSON can be edited.
            licenseKey: 'FREE',
            cloudExpiry: const Value(null),
          ));

      if (outletId != 'default-outlet') {
        await (db.delete(db.outlets)
              ..where((outlet) => outlet.id.equals('default-outlet')))
            .go();
      }

      // Buat user owner
      await db.sessionDao.upsertUser(UsersCompanion(
        id: Value(ownerId),
        outletId: Value(outletId),
        name: const Value('Owner'),
        pin: Value(hashedPin),
        role: const Value('owner'),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));

      await OnboardingService().saveCurrentOutletId(outletId);

      // Update currentOutletIdProvider
      ref.read(currentOutletIdProvider.notifier).state = outletId;

      // Mark setup done
      await OnboardingService().markSetupDone();
      ref.invalidate(isSetupDoneProvider);

      // Store the owner identity, staff PINs, and business configuration in
      // the verified account as soon as setup completes. syncAll handles an
      // offline device gracefully and retries in the background.
      await ref.read(syncServiceProvider).syncAll();

      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Gagal menyimpan data: $e');
    }
  }

  // ── BUILDS ────────────────────────────────────
  Widget _buildWelcome() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: AppTheme.softShadow,
            ),
            child: const SajiaMark(
              size: 76,
              radius: 22,
              backgroundGradient: AppTheme.brandGradient,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Selamat Datang di\nSajia',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 12),
          const Text(
            AppBrand.shortTagline,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 48),
          _Btn(
            label: 'Mulai Setup',
            icon: Icons.arrow_forward_rounded,
            onTap: () {
              setState(() => _isDeviceRecovery = false);
              _goTo(_Step.email);
            },
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              setState(() => _isDeviceRecovery = true);
              _goTo(_Step.email);
            },
            icon: const Icon(Icons.login_rounded),
            label: const Text('Masuk / ganti perangkat'),
          ),
          const SizedBox(height: 16),
          _InfoBox(
            AppDistribution.isPlayStore
                ? 'Gratis untuk mulai jualan: produk, kasir, dan printer tetap bisa dipakai. Lisensi bisnis akan muncul otomatis setelah aktif.'
                : 'Gratis untuk mulai jualan: produk, kasir, dan printer tetap bisa dipakai. Upgrade nanti kalau outlet butuh sync cloud dan kontrol lanjutan.',
          ),
        ],
      );

  Widget _buildEmail() => _Wrapper(
        icon: Icons.verified_user_outlined,
        title: _isDeviceRecovery
            ? 'Masuk sebagai owner'
            : 'Verifikasi email owner',
        subtitle: _isDeviceRecovery
            ? 'Masukkan email pemilik untuk memulihkan outlet di perangkat ini.'
            : 'Email dipakai untuk pemulihan perangkat dan dashboard owner.',
        child: Column(children: [
          _Field(
              ctrl: _emailCtrl,
              label: 'Email owner *',
              hint: 'nama@email.com',
              icon: Icons.alternate_email_rounded,
              type: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendOtp()),
          if (_emailError != null) ...[
            const SizedBox(height: 10),
            Text(_emailError!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          _Btn(
              label: 'Kirim kode OTP',
              icon: Icons.email_outlined,
              loading: _isLoading,
              onTap: _sendOtp),
          TextButton(
              onPressed: () => _goTo(_Step.welcome),
              child: const Text('< Kembali')),
        ]),
      );

  Widget _buildOtp() => _Wrapper(
        icon: Icons.mark_email_read_outlined,
        title: 'Masukkan kode OTP',
        subtitle: 'Kode 6 digit sudah dikirim ke ${_emailCtrl.text.trim()}.',
        child: Column(children: [
          TextField(
            controller: _otpCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            maxLength: 6,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration:
                const InputDecoration(hintText: '••••••', counterText: ''),
            onSubmitted: (_) => _verifyOtp(),
            onChanged: (value) {
              if (value.length == 6 && !_isLoading) {
                unawaited(_verifyOtp());
              }
            },
          ),
          if (_emailError != null) ...[
            const SizedBox(height: 10),
            Text(_emailError!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          _Btn(
              label: 'Verifikasi & lanjut',
              icon: Icons.verified_rounded,
              loading: _isLoading,
              onTap: _verifyOtp),
          TextButton(
              onPressed:
                  _isLoading || _otpCooldownSeconds > 0 ? null : _sendOtp,
              child: Text(
                _otpCooldownSeconds > 0
                    ? 'Kirim ulang dalam $_otpCooldownSeconds detik'
                    : 'Kirim ulang kode',
              )),
        ]),
      );

  Widget _buildOutlet() => _Wrapper(
        icon: Icons.store_rounded,
        title: 'Setup Outlet',
        subtitle: 'Isi informasi dasar tempat usaha kamu',
        child: Column(children: [
          _Field(
              ctrl: _nameCtrl,
              label: 'Nama Outlet *',
              hint: 'Contoh: Sajia Coffee Braga',
              icon: Icons.storefront_outlined),
          const SizedBox(height: 16),
          _Field(
              ctrl: _addressCtrl,
              label: 'Alamat',
              hint: 'Jl. Contoh No. 1',
              icon: Icons.location_on_outlined),
          const SizedBox(height: 16),
          _Field(
              ctrl: _phoneCtrl,
              label: 'Nomor Telepon',
              hint: '08xxxxxxxxxx',
              icon: Icons.phone_outlined,
              type: TextInputType.phone),
          const SizedBox(height: 32),
          _Btn(
            label: 'Lanjut',
            icon: Icons.arrow_forward_rounded,
            onTap: () {
              if (_nameCtrl.text.trim().isEmpty) {
                _snack('Nama outlet wajib diisi');
                return;
              }
              _goTo(_Step.pin);
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _goTo(_Step.email),
            child: const Text('< Kembali'),
          ),
        ]),
      );

  Widget _buildPin() {
    final current = _settingConfirm ? _confirmPin : _pin;
    return _Wrapper(
      icon: Icons.lock_rounded,
      title: _settingConfirm ? 'Konfirmasi PIN' : 'Buat PIN Owner',
      subtitle: _settingConfirm
          ? 'Masukkan PIN yang sama sekali lagi'
          : 'PIN 6 digit untuk login sebagai owner',
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLength, (i) {
            final filled = i < current.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? (_pinError != null ? AppTheme.danger : AppTheme.primary)
                    : const Color(0xFFE5E7EB),
              ),
            );
          }),
        ),
        if (_pinError != null) ...[
          const SizedBox(height: 12),
          Text(_pinError!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
        ],
        const SizedBox(height: 32),
        _Numpad(onDigit: _onPinDigit, onDelete: _onPinDelete),
        if (_isLoading) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          if (_step != _Step.welcome) _ProgressBar(step: _step),
          Expanded(
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: switch (_step) {
                  _Step.welcome => _buildWelcome(),
                  _Step.email => _buildEmail(),
                  _Step.otp => _buildOtp(),
                  _Step.outlet => _buildOutlet(),
                  _Step.pin => _buildPin(),
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ── PROGRESS BAR ──────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final _Step step;
  const _ProgressBar({required this.step});

  static const _steps = [
    _Step.email,
    _Step.otp,
    _Step.outlet,
    _Step.pin,
  ];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexOf(step);
    if (current < 0) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: List.generate(_steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              return Expanded(
                child: Container(
                  height: 2,
                  color: i ~/ 2 < current
                      ? AppTheme.primary
                      : const Color(0xFFE5E7EB),
                ),
              );
            }
            final idx = i ~/ 2;
            final done = idx < current;
            final active = idx == current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    done || active ? AppTheme.primary : const Color(0xFFE5E7EB),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : Text('${idx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              active ? Colors.white : const Color(0xFF9CA3AF),
                        )),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text('Langkah ${current + 1} dari ${_steps.length}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ]),
    );
  }
}

// ── SHARED WIDGETS ────────────────────────────────────────────
class _Wrapper extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  const _Wrapper(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryLight, AppTheme.goldLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.subtleBorder),
              boxShadow: AppTheme.softShadow,
            ),
            child: child,
          ),
        ],
      );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final TextInputType type;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  const _Field(
      {required this.ctrl,
      required this.label,
      required this.hint,
      required this.icon,
      this.type = TextInputType.text,
      this.autofillHints,
      this.textInputAction,
      this.onSubmitted});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
              prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
        ],
      );
}

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;
  const _Btn(
      {required this.label,
      required this.icon,
      this.onTap,
      this.loading = false});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: onTap == null ? null : AppTheme.brandGradient,
          color: onTap == null ? const Color(0xFFD1D5DB) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onTap == null ? null : AppTheme.floatingShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F9FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBAE6FD)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: AppTheme.info, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: AppTheme.info))),
        ]),
      );
}

class _Numpad extends StatelessWidget {
  final Function(String) onDigit;
  final VoidCallback onDelete;
  const _Numpad({required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonSize = (constraints.maxWidth / 3 - 18).clamp(54.0, 72.0);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: keys.length,
          itemBuilder: (context, index) {
            final key = keys[index];
            if (key.isEmpty) return const SizedBox.shrink();
            final isDelete = key == 'del';
            return Center(
              child: Semantics(
                button: true,
                label: isDelete ? 'Hapus digit PIN' : 'Digit $key',
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(buttonSize / 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(buttonSize / 2),
                    onTap: () => isDelete ? onDelete() : onDigit(key),
                    child: Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isDelete
                            ? const Icon(Icons.backspace_outlined,
                                size: 22, color: Color(0xFF6B7280))
                            : Text(key,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                )),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

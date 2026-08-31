import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import '../../core/brand.dart';
import '../../core/onboarding_service.dart';
import '../../core/pin_numpad_layout.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/entities.dart';

class PinLoginPage extends ConsumerStatefulWidget {
  const PinLoginPage({super.key});

  @override
  ConsumerState<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends ConsumerState<PinLoginPage>
    with SingleTickerProviderStateMixin {
  static const _pinLength = 6;
  static const _failedAttemptsKey = 'pin_login_failed_attempts';
  static const _lockoutUntilKey = 'pin_login_lockout_until';
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;
  late final Future<Set<String>> _accountOutletScope;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
    _accountOutletScope = _loadAccountOutletScope();
    unawaited(_restoreLoginGuard());
  }

  Future<Set<String>> _loadAccountOutletScope() async {
    final service = OnboardingService();
    final db = ref.read(databaseProvider);
    final savedScope = await service.getVerifiedOwnerOutletIds();

    if (service.authenticatedUserId != null) {
      try {
        final remoteOutlets = await service
            .getAuthenticatedOwnerOutlets()
            .timeout(const Duration(seconds: 10));
        final remoteScope = remoteOutlets
            .map((outlet) => outlet['id'] as String?)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
        if (remoteScope.isNotEmpty) {
          await db.retainOnlyOutlets(remoteScope);
          await service.saveVerifiedOwnerOutletIds(remoteScope);
          final email = service.authenticatedEmail;
          if (email != null) {
            await service.bindVerifiedAccount(
              authUserId: service.authenticatedUserId!,
              email: email,
              outletIds: remoteScope,
            );
          }
          final currentOutletId = ref.read(currentOutletIdProvider);
          if (!remoteScope.contains(currentOutletId)) {
            final target = remoteScope.first;
            ref.read(currentOutletIdProvider.notifier).state = target;
            await service.saveCurrentOutletId(target);
          }
          return remoteScope;
        }
      } catch (_) {
        // Offline PIN login remains available using the last verified scope.
      }
    }

    if (savedScope.isNotEmpty) return savedScope;
    final currentOutletId = ref.read(currentOutletIdProvider);
    if (currentOutletId.isNotEmpty && currentOutletId != 'default-outlet') {
      return <String>{currentOutletId};
    }
    return const <String>{};
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  int get _lockoutSeconds {
    final until = _lockoutUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining < 1 ? 0 : remaining;
  }

  bool get _isLockedOut => _lockoutSeconds > 0;

  Future<void> _restoreLoginGuard() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_lockoutUntilKey);
    final until =
        value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
    if (!mounted) return;
    setState(() {
      _failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
      _lockoutUntil = until?.isAfter(DateTime.now()) == true ? until : null;
      if (_lockoutUntil != null) {
        _errorMessage =
            'Terlalu banyak PIN salah. Coba lagi dalam $_lockoutSeconds detik.';
      }
    });
    if (_lockoutUntil != null) _startLockoutTicker();
  }

  void _startLockoutTicker() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final seconds = _lockoutSeconds;
      if (seconds == 0) {
        timer.cancel();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_lockoutUntilKey);
        if (!mounted) return;
        setState(() {
          _lockoutUntil = null;
          _pin = '';
          _errorMessage = 'Silakan masukkan PIN kembali.';
        });
      } else {
        setState(() => _errorMessage =
            'Terlalu banyak PIN salah. Coba lagi dalam $seconds detik.');
      }
    });
  }

  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_failedAttemptsKey, _failedAttempts);
    if (_failedAttempts < 5) return;

    final lockoutLevel = ((_failedAttempts - 5) ~/ 5).clamp(0, 4);
    final seconds = (30 * (1 << lockoutLevel)).clamp(30, 300);
    _lockoutUntil = DateTime.now().add(Duration(seconds: seconds));
    await prefs.setInt(
      _lockoutUntilKey,
      _lockoutUntil!.millisecondsSinceEpoch,
    );
    if (mounted) _startLockoutTicker();
  }

  Future<void> _clearLoginGuard() async {
    _failedAttempts = 0;
    _lockoutUntil = null;
    _lockoutTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockoutUntilKey);
  }

  void _onDigit(String digit) {
    if (_isLockedOut) {
      setState(() => _errorMessage =
          'Terlalu banyak PIN salah. Coba lagi dalam $_lockoutSeconds detik.');
      return;
    }
    if (_pin.length >= _pinLength || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += digit;
      _errorMessage = null;
    });
    if (_pin.length == _pinLength) _tryLogin();
  }

  void _onDelete() {
    if (_pin.isEmpty || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _tryLogin() async {
    if (_pin.length != _pinLength || _isLockedOut) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 250));

    final db = ref.read(databaseProvider);
    final currentOutletId = ref.read(currentOutletIdProvider);
    final accountOutletIds = await _accountOutletScope;
    final users =
        await db.sessionDao.getActiveUsersForOutlets(accountOutletIds);
    final matchingUsers = <User>[];

    for (final candidate in users) {
      if (PinHasher.verify(_pin, candidate.outletId, candidate.pin)) {
        matchingUsers.add(candidate);
      }
    }

    if (!mounted) return;

    if (matchingUsers.length > 1) {
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _errorMessage =
            'PIN dipakai lebih dari satu user. Minta owner ganti salah satu PIN.';
        _pin = '';
        _isLoading = false;
      });
      return;
    }

    final user = matchingUsers.isEmpty ? null : matchingUsers.first;
    final shouldUpgradePinHash =
        user != null && PinHasher.isLegacyHash(user.pin);

    if (user != null) {
      await _clearLoginGuard();
      if (shouldUpgradePinHash) {
        await db.sessionDao.upsertUser(UsersCompanion(
          id: Value(user.id),
          outletId: Value(user.outletId),
          name: Value(user.name),
          pin: Value(PinHasher.hash(_pin, user.outletId)),
          role: Value(user.role),
          isActive: Value(user.isActive),
          updatedAt: Value(DateTime.now()),
        ));
        if (!mounted) return;
      }
      final assignedOutletIds = await db.sessionDao.getUserOutletIds(user.id);
      if (!mounted) return;
      final accessibleOutletIds = user.role == 'owner'
          ? const <String>[]
          : assignedOutletIds.isEmpty
              ? <String>[user.outletId]
              : assignedOutletIds;

      final currentOutletExists = currentOutletId.isNotEmpty &&
          await (db.select(db.outlets)
                    ..where((outlet) => outlet.id.equals(currentOutletId)))
                  .getSingleOrNull() !=
              null;
      var targetOutletId = currentOutletId;
      if (user.role == 'owner') {
        if (!currentOutletExists || currentOutletId == 'default-outlet') {
          targetOutletId = user.outletId;
        }
      } else if (!accessibleOutletIds.contains(currentOutletId) &&
          accessibleOutletIds.isNotEmpty) {
        targetOutletId = accessibleOutletIds.first;
      }
      if (targetOutletId != currentOutletId) {
        ref.read(currentOutletIdProvider.notifier).state = targetOutletId;
        await OnboardingService().saveCurrentOutletId(targetOutletId);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ref.read(currentUserProvider.notifier).state = AppUser(
        id: user.id,
        name: user.name,
        role: user.role,
        outletId: user.outletId,
        assignedOutletIds: accessibleOutletIds,
      );
      context.go('/cashier');
    } else {
      await _recordFailedAttempt();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _errorMessage = _isLockedOut
            ? 'Terlalu banyak PIN salah. Coba lagi dalam $_lockoutSeconds detik.'
            : 'PIN salah. Sisa ${5 - (_failedAttempts % 5)} percobaan sebelum dikunci sementara.';
        _pin = '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width > 600 ? 420.0 : 380.0;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFAFBFA), Color(0xFFF1F5F4)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            const _LoginGlow(
              top: -90,
              right: -80,
              size: 240,
              opacity: 0.10,
              color: AppTheme.action,
            ),
            const _LoginGlow(
              bottom: 90,
              left: -110,
              size: 260,
              opacity: 0.07,
              color: AppBrand.accent,
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 18 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        children: [
                          const SizedBox(height: 18),
                          const _SajiaLogo(),
                          const SizedBox(height: 34),
                          _LoginPanel(
                            isLoading: _isLoading,
                            pinLength: _pin.length,
                            errorMessage: _errorMessage,
                            shakeAnim: _shakeAnim,
                            shakeController: _shakeCtrl,
                            onDigit: _onDigit,
                            onDelete: _onDelete,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'PIN tersimpan aman di akun bisnis dan berlaku di perangkat yang dipulihkan.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  final bool isLoading;
  final int pinLength;
  final String? errorMessage;
  final Animation<double> shakeAnim;
  final AnimationController shakeController;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  const _LoginPanel({
    required this.isLoading,
    required this.pinLength,
    required this.errorMessage,
    required this.shakeAnim,
    required this.shakeController,
    required this.onDigit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.subtleBorder),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          Text(
            isLoading ? 'Memeriksa PIN...' : 'Masukkan PIN',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: shakeAnim,
            builder: (_, child) {
              final offset = shakeController.isAnimating
                  ? 10 * (0.5 - (shakeAnim.value - 0.5).abs()) * 2
                  : 0.0;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final filled = index < pinLength;
                final isError = errorMessage != null;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  width: filled ? 17 : 12,
                  height: filled ? 17 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? (isError ? AppTheme.danger : AppTheme.action)
                        : AppTheme.neutralSoft,
                    border: Border.all(
                      color: filled
                          ? Colors.transparent
                          : AppTheme.borderColor,
                    ),
                  ),
                );
              }),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: errorMessage != null ? 34 : 16,
            alignment: Alignment.center,
            child: Text(
              errorMessage ?? '',
              style: const TextStyle(
                color: AppTheme.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _Numpad(onDigit: onDigit, onDelete: onDelete),
        ],
      ),
    );
  }
}

class _LoginGlow extends StatelessWidget {
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final double size;
  final double opacity;
  final Color color;

  const _LoginGlow({
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.size,
    required this.opacity,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _SajiaLogo extends StatelessWidget {
  const _SajiaLogo();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: const SajiaLogoLockup(
        markSize: 76,
        markRadius: 24,
        gap: 16,
        nameFontSize: 34,
        descriptorFontSize: 10,
        textColor: AppTheme.textPrimary,
        descriptorColor: AppTheme.textSecondary,
        markBackgroundColor: Colors.white,
      ),
    );
  }
}

class _Numpad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  const _Numpad({required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonSize = pinNumpadButtonSize(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            mainAxisExtent: buttonSize,
          ),
          itemCount: keys.length,
          itemBuilder: (context, index) {
            final key = keys[index];
            if (key.isEmpty) return const SizedBox.shrink();

            final isDelete = key == 'del';
            return Center(
              child: _NumpadButton(
                label: key,
                size: buttonSize,
                isDelete: isDelete,
                onTap: isDelete ? onDelete : () => onDigit(key),
              ),
            );
          },
        );
      },
    );
  }
}

class _NumpadButton extends StatefulWidget {
  final String label;
  final double size;
  final bool isDelete;
  final VoidCallback onTap;

  const _NumpadButton({
    required this.label,
    required this.size,
    required this.isDelete,
    required this.onTap,
  });

  @override
  State<_NumpadButton> createState() => _NumpadButtonState();
}

class _NumpadButtonState extends State<_NumpadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isDelete
                ? AppTheme.neutralSoft
                : Colors.white,
            border: Border.all(
              color: AppTheme.borderColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: widget.isDelete
                ? Icon(
                    Icons.backspace_outlined,
                    color: AppTheme.textSecondary,
                    size: 22,
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

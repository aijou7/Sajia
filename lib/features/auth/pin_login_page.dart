import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/providers.dart';
import '../../core/brand.dart';
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
  String _pin = '';
  String? _errorMessage;
  bool _isLoading = false;
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
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
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
    if (_pin.length != _pinLength) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 250));

    final db = ref.read(databaseProvider);
    final currentOutletId = ref.read(currentOutletIdProvider);
    final users = await db.sessionDao.getActiveUsers();
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
      if (user.role != 'owner' &&
          !accessibleOutletIds.contains(currentOutletId) &&
          accessibleOutletIds.isNotEmpty) {
        ref.read(currentOutletIdProvider.notifier).state =
            accessibleOutletIds.first;
      }
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
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _errorMessage = 'PIN salah, coba lagi';
        _pin = '';
        _isLoading = false;
      });
    }
  }

  void _devLogin() {
    ref.read(currentUserProvider.notifier).state = const AppUser(
      id: 'dev-user',
      name: 'Owner',
      role: 'owner',
      outletId: 'default-outlet',
      assignedOutletIds: [],
    );
    context.go('/cashier');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width > 600 ? 420.0 : 380.0;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: Stack(
          children: [
            const _LoginGlow(top: -90, right: -80, size: 240, opacity: 0.18),
            const _LoginGlow(bottom: 90, left: -110, size: 260, opacity: 0.12),
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
                          const SizedBox(height: 14),
                          const Text(
                            AppBrand.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppBrand.descriptor,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 13,
                              letterSpacing: 0.4,
                            ),
                          ),
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
                          TextButton(
                            onPressed: _devLogin,
                            child: Text(
                              'Masuk sebagai demo',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.58),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 34,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            isLoading ? 'Memeriksa PIN...' : 'Masukkan PIN',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
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
                        ? (isError ? AppTheme.danger : AppTheme.gold)
                        : Colors.white.withValues(alpha: 0.14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.42),
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
                color: Color(0xFFFFC4C4),
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

  const _LoginGlow({
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.size,
    required this.opacity,
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
              Colors.white.withValues(alpha: opacity),
              Colors.white.withValues(alpha: 0),
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.26),
            width: 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SajiaMark(
          size: 76,
          radius: 24,
          backgroundColor: Colors.white.withValues(alpha: 0.16),
        ),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 14,
        childAspectRatio: 74 / 70,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        if (key.isEmpty) return const SizedBox.shrink();

        final isDelete = key == 'del';
        return Center(
          child: _NumpadButton(
            label: key,
            isDelete: isDelete,
            onTap: isDelete ? onDelete : () => onDigit(key),
          ),
        );
      },
    );
  }
}

class _NumpadButton extends StatefulWidget {
  final String label;
  final bool isDelete;
  final VoidCallback onTap;

  const _NumpadButton({
    required this.label,
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
          width: 74,
          height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isDelete
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.7,
            ),
          ),
          child: Center(
            child: widget.isDelete
                ? Icon(
                    Icons.backspace_outlined,
                    color: Colors.white.withValues(alpha: 0.72),
                    size: 22,
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
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

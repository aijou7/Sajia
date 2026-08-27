import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/brand.dart';

const _startupBackground = Color(0xFFFAFAFA);

class SajiaStartupSplash extends StatefulWidget {
  const SajiaStartupSplash({super.key});

  @override
  State<SajiaStartupSplash> createState() => _SajiaStartupSplashState();
}

class _SajiaStartupSplashState extends State<SajiaStartupSplash>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _motionController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final introCurve = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(introCurve);
    _scale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutBack,
      ),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(introCurve);

    _introController.forward();
    _motionController.repeat();
  }

  @override
  void dispose() {
    _introController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppBrand.primary,
          surface: _startupBackground,
        ),
        scaffoldBackgroundColor: _startupBackground,
      ),
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _AmbientAccent(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 5),
                    FadeTransition(
                      opacity: _fade,
                      alwaysIncludeSemantics: true,
                      child: SlideTransition(
                        position: _slide,
                        child: ScaleTransition(
                          scale: _scale,
                          child: _AnimatedBrand(
                            motionController: _motionController,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 4),
                    FadeTransition(
                      opacity: _fade,
                      alwaysIncludeSemantics: true,
                      child: _LoadingStatus(
                        motionController: _motionController,
                      ),
                    ),
                    const SizedBox(height: 44),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientAccent extends StatelessWidget {
  const _AmbientAccent();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -90,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppBrand.primaryLight.withValues(alpha: 0.72),
                    AppBrand.primaryLight.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppBrand.primaryLight.withValues(alpha: 0.48),
                    AppBrand.primaryLight.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBrand extends StatelessWidget {
  final Animation<double> motionController;

  const _AnimatedBrand({required this.motionController});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: '${AppBrand.name}, ${AppBrand.descriptor}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: motionController,
              builder: (context, child) {
                final cycle = reduceMotion ? 0.25 : motionController.value;
                final breathing =
                    1 + (math.sin(cycle * math.pi * 2) * 0.014);
                return SizedBox(
                  width: 154,
                  height: 154,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _PulseRing(progress: cycle),
                      _PulseRing(progress: (cycle + 0.5) % 1),
                      Transform.scale(
                        scale: breathing,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: const SajiaMark(
                            size: 104,
                            radius: 28,
                            showBadge: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              AppBrand.name,
              style: TextStyle(
                color: AppBrand.ink,
                fontSize: 38,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppBrand.descriptor.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppBrand.mutedInk,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  final double progress;

  const _PulseRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.78 + (progress * 0.34),
      child: Opacity(
        opacity: (1 - progress) * 0.22,
        child: Container(
          width: 142,
          height: 142,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppBrand.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _LoadingStatus extends StatelessWidget {
  final Animation<double> motionController;

  const _LoadingStatus({required this.motionController});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: 'Sajia sedang disiapkan',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: motionController,
              builder: (context, child) {
                final cycle = reduceMotion ? 0.25 : motionController.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final phase = (cycle + (index * 0.16)) % 1;
                    final lift = math
                        .sin(phase * math.pi * 2)
                        .clamp(0.0, 1.0)
                        .toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Transform.translate(
                        offset: Offset(0, -3 * lift),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              AppBrand.primaryLight,
                              AppBrand.primary,
                              0.35 + (lift * 0.65),
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Menyiapkan Sajia',
              style: TextStyle(
                color: AppBrand.mutedInk,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SajiaStartupError extends StatelessWidget {
  final VoidCallback onRetry;

  const SajiaStartupError({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        backgroundColor: _startupBackground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SajiaMark(size: 76, radius: 22),
                    const SizedBox(height: 28),
                    const Text(
                      'Sajia belum dapat disiapkan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppBrand.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Periksa koneksi internet, lalu coba lagi. Data di perangkat tetap aman.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppBrand.mutedInk,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppBrand.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(180, 50),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
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
}

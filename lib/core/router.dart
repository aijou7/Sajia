import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import '../features/auth/pin_login_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/shared/main_scaffold.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(routerRefreshProvider);
  final setupDone = ref.watch(isSetupDoneProvider).value;
  final user = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/onboarding',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final path = state.uri.path;

      if (setupDone == null) return null;

      if (!setupDone) {
        return path == '/onboarding' ? null : '/onboarding';
      }

      if (path == '/onboarding') return '/login';
      if (user == null && path != '/login') return '/login';
      if (user != null && path == '/login') return '/cashier';
      if (user != null &&
          path == '/history' &&
          !user.canManageOperations &&
          !user.canViewFinancialReports) {
        return '/cashier';
      }
      if (user != null &&
          (path == '/dashboard' || path == '/reports') &&
          !user.canViewFinancialReports) {
        return '/cashier';
      }
      if (user != null && path == '/settings' && !user.canManageOperations) {
        return '/cashier';
      }

      return null;
    },
    routes: [
      GoRoute(
          path: '/onboarding', builder: (ctx, state) => const OnboardingPage()),
      GoRoute(path: '/login', builder: (ctx, state) => const PinLoginPage()),
      GoRoute(
          path: '/cashier',
          builder: (ctx, state) => const MainScaffold(currentIndex: 0)),
      GoRoute(
          path: '/tables',
          builder: (ctx, state) => const MainScaffold(currentIndex: 1)),
      GoRoute(
          path: '/menu',
          builder: (ctx, state) => const MainScaffold(currentIndex: 2)),
      GoRoute(
          path: '/history',
          builder: (ctx, state) => const MainScaffold(currentIndex: 3)),
      GoRoute(
          path: '/reports',
          builder: (ctx, state) => const MainScaffold(currentIndex: 5)),
      GoRoute(
          path: '/dashboard',
          builder: (ctx, state) => const MainScaffold(currentIndex: 4)),
      GoRoute(
          path: '/settings',
          builder: (ctx, state) => const MainScaffold(currentIndex: 6)),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.explore_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Halaman tidak ditemukan',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kembali ke kasir untuk melanjutkan pekerjaan.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => ctx.go('/cashier'),
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: const Text('Kembali ke kasir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
});

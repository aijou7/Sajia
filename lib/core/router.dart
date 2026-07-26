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
      body: Center(child: Text('404: ${state.error}')),
    ),
  );
});

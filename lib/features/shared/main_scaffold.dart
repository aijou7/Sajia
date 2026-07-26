import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers.dart';
import '../cashier/cashier_page.dart';
import '../orders/tables_page.dart';
import '../menu/menu_page.dart';
import '../cashier/sales_history_page.dart';
import '../dashboard/business_dashboard_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final int currentIndex;
  const MainScaffold({super.key, required this.currentIndex});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  late int _currentIndex;

  Widget _pageForIndex(int index) => switch (index) {
        0 => const CashierPage(),
        1 => const TablesPage(),
        2 => const MenuPage(),
        3 => const SalesHistoryPage(),
        4 => const BusinessDashboardPage(),
        5 => const ReportsPage(),
        6 => const SettingsPage(),
        _ => const CashierPage(),
      };

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _currentIndex = widget.currentIndex;
    }
  }

  void _goTo(int index, String path) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }

    final currentPath = GoRouterState.of(context).uri.path;
    if (currentPath != path) {
      context.go(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canViewFinancialReports = user?.canViewFinancialReports == true;

    return Scaffold(
      body: KeyedSubtree(
        key: ValueKey('main-page-$_currentIndex'),
        child: _pageForIndex(_currentIndex),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
              top: BorderSide(color: AppTheme.subtleBorder, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDeep.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(children: [
              _NavItem(
                icon: Icons.point_of_sale_outlined,
                activeIcon: Icons.point_of_sale_rounded,
                label: 'Kasir',
                selected: _currentIndex == 0,
                onTap: () => _goTo(0, '/cashier'),
              ),
              _NavItem(
                icon: Icons.table_bar_outlined,
                activeIcon: Icons.table_bar_rounded,
                label: 'Meja',
                selected: _currentIndex == 1,
                onTap: () => _goTo(1, '/tables'),
              ),
              _NavItem(
                icon: Icons.menu_book_outlined,
                activeIcon: Icons.menu_book_rounded,
                label: 'Menu',
                selected: _currentIndex == 2,
                onTap: () => _goTo(2, '/menu'),
              ),
              _NavItem(
                icon: Icons.history_outlined,
                activeIcon: Icons.history_rounded,
                label: 'Riwayat',
                selected: _currentIndex == 3,
                onTap: () => _goTo(3, '/history'),
              ),
              if (canViewFinancialReports) ...[
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  selected: _currentIndex == 4,
                  onTap: () => _goTo(4, '/dashboard'),
                ),
                _NavItem(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart_rounded,
                  label: 'Laporan',
                  selected: _currentIndex == 5,
                  onTap: () => _goTo(5, '/reports'),
                ),
              ],
              _NavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: 'Setting',
                selected: _currentIndex == 6,
                onTap: () => _goTo(6, '/settings'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: selected ? 38 : 34,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedScale(
                scale: selected ? 1.05 : 1,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected ? activeIcon : icon,
                  color: selected ? AppTheme.primary : const Color(0xFFB0B7C3),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppTheme.primary : const Color(0xFFB0B7C3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

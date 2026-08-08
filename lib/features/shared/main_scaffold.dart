import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/providers.dart';
import '../cashier/cashier_page.dart';
import '../orders/tables_page.dart';
import '../menu/menu_page.dart';
import '../cashier/sales_history_page.dart';
import '../dashboard/business_dashboard_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import 'more_page.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final int currentIndex;
  const MainScaffold({super.key, required this.currentIndex});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  late int _currentIndex;
  late final List<Widget?> _pages;

  Widget _pageForIndex(int index) => switch (index) {
        0 => const CashierPage(),
        1 => const TablesPage(),
        2 => const MenuPage(),
        3 => const SalesHistoryPage(),
        4 => const BusinessDashboardPage(),
        5 => const ReportsPage(),
        6 => const SettingsPage(),
        7 => MorePage(onOpenDestination: _goTo),
        _ => const CashierPage(),
      };

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _pages = List<Widget?>.filled(8, null);
    _pages[_currentIndex] = _pageForIndex(_currentIndex);
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _currentIndex = widget.currentIndex;
      _pages[_currentIndex] ??= _pageForIndex(_currentIndex);
    }
  }

  void _goTo(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _pages[index] ??= _pageForIndex(index);
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final canViewHistory = user?.canManageOperations == true ||
        user?.canViewFinancialReports == true;
    final canViewReports = user?.canViewFinancialReports == true;
    final canManageSettings = user?.canManageOperations == true;
    final isRestrictedDestination = switch (_currentIndex) {
      3 => !canViewHistory,
      4 || 5 => !canViewReports,
      6 => !canManageSettings,
      _ => false,
    };
    final visibleIndex = isRestrictedDestination ? 0 : _currentIndex;

    if (isRestrictedDestination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentIndex != 0) _goTo(0);
      });
    }
    _pages[visibleIndex] ??= _pageForIndex(visibleIndex);
    final moreSelected = visibleIndex >= 4;

    return Scaffold(
      body: IndexedStack(
        index: visibleIndex,
        children: List<Widget>.generate(
          _pages.length,
          (index) => _pages[index] ?? const SizedBox.shrink(),
        ),
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
                selected: visibleIndex == 0,
                onTap: () => _goTo(0),
              ),
              _NavItem(
                icon: Icons.table_bar_outlined,
                activeIcon: Icons.table_bar_rounded,
                label: 'Meja',
                selected: visibleIndex == 1,
                onTap: () => _goTo(1),
              ),
              _NavItem(
                icon: Icons.menu_book_outlined,
                activeIcon: Icons.menu_book_rounded,
                label: 'Menu',
                selected: visibleIndex == 2,
                onTap: () => _goTo(2),
              ),
              if (canViewHistory)
                _NavItem(
                  icon: Icons.history_outlined,
                  activeIcon: Icons.history_rounded,
                  label: 'Riwayat',
                  selected: visibleIndex == 3,
                  onTap: () => _goTo(3),
                ),
              _NavItem(
                icon: Icons.grid_view_outlined,
                activeIcon: Icons.grid_view_rounded,
                label: 'Lainnya',
                selected: moreSelected,
                onTap: () => _goTo(7),
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
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 38,
                  height: 30,
                  decoration: BoxDecoration(
                    color:
                        selected ? AppTheme.primaryLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    selected ? activeIcon : icon,
                    color:
                        selected ? AppTheme.primary : const Color(0xFFB0B7C3),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color:
                        selected ? AppTheme.primary : const Color(0xFFB0B7C3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

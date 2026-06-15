import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_navigation.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/testing/test_keys.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/ads/web_ad_rail.dart';

/// Main scaffold — persistent bottom navigation via [StatefulNavigationShell].
///
/// Tab switches call [StatefulNavigationShell.goBranch] (no stack growth).
/// Each tab keeps its own nested navigator for drill-down pages.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  void _onTabTap(BuildContext context, int index) {
    AppNavigation.switchTab(
      context,
      index,
      toRoot: index == navigationShell.currentIndex,
    );
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.read<DashboardBloc>().add(DashboardRefreshRequested());
      });
    }
  }

  void _handleBack(BuildContext context) {
    AppNavigation.handleNestedBack(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: ResponsiveHelper.isDesktop(context)
          ? _buildDesktop(context, currentIndex)
          : _buildMobile(context, currentIndex),
    );
  }

  Widget _buildDesktop(BuildContext context, int currentIndex) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            _DesktopSidebar(
              currentIndex: currentIndex,
              onTap: (i) => _onTabTap(context, i),
            ),
            const VerticalDivider(width: 1, color: AppColors.divider),
            Expanded(child: navigationShell),
            if (WebAdRail.shouldShow(context)) const WebAdRail(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context, int currentIndex) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: navigationShell,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => _onTabTap(context, i),
          items: const [
            BottomNavigationBarItem(
              key: TestKeys.navHome,
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              key: TestKeys.navSubjects,
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book_rounded),
              label: 'Subjects',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              key: TestKeys.navProfile,
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _DesktopSidebar({required this.currentIndex, required this.onTap});

  static const _navItems = [
    _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _NavItem(Icons.menu_book_rounded, Icons.menu_book_outlined, 'Subjects'),
    _NavItem(Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Analytics'),
    _NavItem(Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Container(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ExamSaathi',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            for (int i = 0; i < _navItems.length; i++)
              _SidebarNavItem(
                item: _navItems[i],
                isActive: currentIndex == i,
                onTap: () => onTap(i),
              ),
            const Spacer(),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ExamSaathi v1.0',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;

  const _NavItem(this.activeIcon, this.inactiveIcon, this.label);
}

class _SidebarNavItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: isActive
                ? BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  )
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
            child: Row(
              children: [
                Icon(
                  isActive ? item.activeIcon : item.inactiveIcon,
                  size: 20,
                  color: isActive ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : AppColors.textSecondary,
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_helper.dart';

/// Main scaffold — bottom navigation on mobile/tablet, sidebar on desktop.
class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  static const _tabs = [
    '/home',
    '/subjects',
    '/analytics',
    '/profile',
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    if (ResponsiveHelper.isDesktop(context)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Row(
            children: [
              _DesktopSidebar(
                currentIndex: currentIndex,
                onTap: (i) => context.go(_tabs[i]),
              ),
              const VerticalDivider(width: 1, color: AppColors.divider),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: child,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
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
            // ── App brand ───────────────────────────────────────────────
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

            // ── Nav items ───────────────────────────────────────────────
            for (int i = 0; i < _navItems.length; i++)
              _SidebarNavItem(
                item: _navItems[i],
                isActive: currentIndex == i,
                onTap: () => onTap(i),
              ),

            const Spacer(),

            // ── Footer ──────────────────────────────────────────────────
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
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
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

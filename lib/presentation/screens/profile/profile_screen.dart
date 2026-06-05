import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/dashboard/dashboard_bloc.dart';
import '../../widgets/manual_sync_button.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          final user = state is DashboardLoaded ? state.dashboard.user : null;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isDesktop(context) ? 700 : double.infinity,
              ),
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Avatar
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        user?.firstName[0].toUpperCase() ?? 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.fullName ?? 'Student',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (user?.selectedExamName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user!.selectedExamName!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                // Streak stat
                if (user != null) ...[
                  _StatRow(
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.streakFire,
                    label: 'Study Streak',
                    value: '${user.studyStreakDays} days',
                  ),
                  const Divider(height: 24),
                ],
                const Divider(height: 24),
                ManualSyncButton(
                  onComplete: () =>
                      context.read<DashboardBloc>().add(DashboardLoadRequested()),
                ),
                const SizedBox(height: 16),
                _ProfileTile(
                  icon: Icons.school_outlined,
                  label: 'My Exams',
                  onTap: () => context.go('/my-exams'),
                ),
                _ProfileTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () {},
                ),
                _ProfileTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & Support',
                  onTap: () {},
                ),
                const Divider(height: 24),
                _ProfileTile(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  color: AppColors.error,
                  onTap: () {
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                    context.go('/login');
                  },
                ),
              ],
            ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: color, fontSize: 15)),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w500)),
      trailing: color == null
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.textHint)
          : null,
      onTap: onTap,
    );
  }
}

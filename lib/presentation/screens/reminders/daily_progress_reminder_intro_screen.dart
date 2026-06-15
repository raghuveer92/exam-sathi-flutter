import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/reminders/daily_progress_reminder_service.dart';
import '../../../data/repositories/daily_progress_reminder_repository.dart';

/// Educational intro shown once on the dashboard before any permission prompt.
class DailyProgressReminderIntroScreen extends StatelessWidget {
  const DailyProgressReminderIntroScreen({super.key});

  Future<void> _onMaybeLater(BuildContext context) async {
    await GetIt.I<DailyProgressReminderRepository>().snoozeReminderIntro();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _onEnableReminder(BuildContext context) async {
    final repository = GetIt.I<DailyProgressReminderRepository>();
    final service = GetIt.I<DailyProgressReminderService>();

    final granted = await service.requestPermissions();
    await repository.markReminderIntroShown();
    if (!context.mounted) return;

    if (granted) {
      await repository.savePreference(
        repository.getPreference().copyWith(enabled: true),
      );
      await service.refreshSchedule();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      context.push('/daily-progress-reminder');
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Notifications are off. You can enable reminders anytime from Profile → Daily Progress Reminder.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _onMaybeLater(context),
                  child: const Text('Maybe Later'),
                ),
              ),
              const Spacer(flex: 1),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Center(
                  child: Text('🔔', style: TextStyle(fontSize: 56)),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Stay Consistent with Daily Reminders',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A gentle nudge at the end of the day helps you log progress and keep your study streak alive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),
              const _BenefitRow(
                icon: Icons.track_changes_rounded,
                title: 'Never forget to log progress',
                subtitle:
                    'We remind you only if you haven\'t studied or marked a rest day.',
              ),
              const SizedBox(height: 16),
              const _BenefitRow(
                icon: Icons.local_fire_department_outlined,
                title: 'Protect your streak',
                subtitle: 'Small daily check-ins build long-term consistency.',
              ),
              const SizedBox(height: 16),
              const _BenefitRow(
                icon: Icons.schedule_rounded,
                title: 'You choose the time',
                subtitle: 'Pick a reminder time that fits your routine.',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _onEnableReminder(context),
                  child: const Text(
                    'Enable Reminder',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => _onMaybeLater(context),
                  child: const Text(
                    'Not Now',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

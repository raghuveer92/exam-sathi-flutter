import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/reminders/daily_progress_reminder_service.dart';
import '../../../data/models/daily_progress_reminder_model.dart';
import '../../../data/repositories/daily_progress_reminder_repository.dart';

class DailyProgressReminderScreen extends StatefulWidget {
  const DailyProgressReminderScreen({super.key});

  @override
  State<DailyProgressReminderScreen> createState() =>
      _DailyProgressReminderScreenState();
}

class _DailyProgressReminderScreenState
    extends State<DailyProgressReminderScreen> {
  late final DailyProgressReminderRepository _repository;
  late DailyProgressReminderPreference _preference;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = GetIt.I<DailyProgressReminderRepository>();
    _preference = _repository.getPreference();
    _refresh();
  }

  Future<void> _refresh() async {
    await _repository.refreshPreferenceFromBackend();
    if (!mounted) return;
    setState(() => _preference = _repository.getPreference());
    await GetIt.I<DailyProgressReminderService>().refreshSchedule();
  }

  Future<void> _save(DailyProgressReminderPreference next) async {
    setState(() {
      _preference = next;
      _saving = true;
    });
    await _repository.savePreference(next);
    await GetIt.I<DailyProgressReminderService>().refreshSchedule();
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<void> _onToggleChanged(bool value) async {
    if (value) {
      final granted =
          await GetIt.I<DailyProgressReminderService>().requestPermissions();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission is required to enable reminders. '
              'You can allow it from system settings anytime.',
            ),
          ),
        );
        return;
      }
      await _repository.markReminderIntroShown();
    }
    await _save(_preference.copyWith(enabled: value));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _preference.timeOfDay,
    );
    if (picked == null) return;
    await _save(_preference.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Progress Reminder')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ReminderToggleCard(
            enabled: _preference.enabled,
            saving: _saving,
            onChanged: _onToggleChanged,
          ),
          const SizedBox(height: 28),
          Text(
            'Reminder Time',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          _SoftCard(
            child: ListTile(
              enabled: _preference.enabled,
              contentPadding: EdgeInsets.zero,
              leading: const _IconBubble(icon: Icons.schedule_rounded),
              title: Text(
                _preference.displayTime,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _preference.enabled ? _pickTime : null,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We\'ll remind you at the selected time if you haven\'t added any study hours or completed any topics on that day.',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'How it works',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          const _HowItWorksRow(
            icon: Icons.event_available_outlined,
            text:
                'Reminder will be sent only if you haven\'t logged any study today.',
          ),
          const _HowItWorksRow(
            icon: Icons.notifications_active_outlined,
            text:
                'You can mark Didn\'t Study if you took a break. That\'s okay!',
          ),
          const _HowItWorksRow(
            icon: Icons.star_border_rounded,
            text: 'Keep your streak alive and stay consistent.',
          ),
        ],
      ),
    );
  }
}

class _ReminderToggleCard extends StatelessWidget {
  const _ReminderToggleCard({
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });

  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Row(
        children: [
          const _IconBubble(icon: Icons.notifications_none_rounded),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Reminder',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Get reminded if you don\'t log your progress in a day.',
                  style:
                      TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: AppColors.primary,
            onChanged: saving ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: AppColors.primary),
    );
  }
}

class _HowItWorksRow extends StatelessWidget {
  const _HowItWorksRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

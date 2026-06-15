import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/daily_progress_reminder_model.dart';
import '../../data/repositories/daily_progress_reminder_repository.dart';
import '../constants/app_colors.dart';
import '../router/app_navigation.dart';

class DailyProgressReminderService {
  DailyProgressReminderService({
    required DailyProgressReminderRepository repository,
    Logger? logger,
  })  : _repository = repository,
        _logger = logger ?? Logger();

  static const int _notificationId = 2200;
  static const String _payload = 'daily_progress_reminder';
  static const String _noStudyAction = 'daily_progress_no_study';
  static const String _updateProgressAction = 'daily_progress_update';

  final DailyProgressReminderRepository _repository;
  final Logger _logger;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    tz.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const init = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(
      init,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> refreshSchedule() async {
    final preference = _repository.getPreference();
    if (!preference.enabled) {
      _logger.i('[DailyReminder] disabled; cancelling notification');
      await cancelTodayReminder();
      return;
    }
    if (!_repository.shouldRemindToday()) {
      _logger.i(
        '[DailyReminder] skipped; progress/no-study already recorded today',
      );
      await cancelTodayReminder();
      return;
    }
    await scheduleTodayReminder(preference);
  }

  Future<void> scheduleTodayReminder(
    DailyProgressReminderPreference preference,
  ) async {
    if (kIsWeb) return;
    await initialize();
    final now = DateTime.now();
    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      preference.hour,
      preference.minute,
    );
    if (!scheduled.isAfter(now)) {
      _logger.i(
        '[DailyReminder] selected time ${preference.displayTime} has passed',
      );
      await cancelTodayReminder();
      return;
    }

    final scheduleMode = await _resolveAndroidScheduleMode();

    await _notifications.zonedSchedule(
      _notificationId,
      'Daily Progress Reminder',
      'Looks like you haven\'t added any study progress today.',
      tz.TZDateTime.from(scheduled, tz.local),
      _details(),
      androidScheduleMode: scheduleMode,
      payload: _payload,
    );
    final pending = await _notifications.pendingNotificationRequests();
    _logger.i(
      '[DailyReminder] scheduled ${scheduled.toIso8601String()} '
      'mode=$scheduleMode pending=${pending.map((e) => e.id).toList()}',
    );
  }

  Future<void> cancelTodayReminder() async {
    if (kIsWeb) return;
    await initialize();
    await _notifications.cancel(_notificationId);
    _logger.i('[DailyReminder] cancelled notification $_notificationId');
  }

  Future<void> _requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<AndroidScheduleMode> _resolveAndroidScheduleMode() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canScheduleExact =
        await android?.canScheduleExactNotifications() ?? false;
    if (canScheduleExact) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    _logger.w(
      '[DailyReminder] exact alarm permission unavailable; using inexact alarm',
    );
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      'daily_progress_reminder',
      'Daily Progress Reminder',
      channelDescription: 'Night reminder to log daily study progress.',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _noStudyAction,
          'Didn\'t Study',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          _updateProgressAction,
          'Update Progress',
          showsUserInterface: true,
        ),
      ],
    );
    const ios = DarwinNotificationDetails(
      categoryIdentifier: 'daily_progress_reminder',
    );
    return const NotificationDetails(android: android, iOS: ios);
  }

  Future<void> _handleNotificationResponse(
    NotificationResponse response,
  ) async {
    if (response.payload != _payload) return;
    if (response.actionId == _noStudyAction) {
      await _repository.markNoStudyDay();
      await cancelTodayReminder();
      return;
    }
    _pendingAction.add(DailyProgressReminderAction.updateProgress);
  }

  final StreamController<DailyProgressReminderAction> _pendingAction =
      StreamController<DailyProgressReminderAction>.broadcast();

  Stream<DailyProgressReminderAction> get pendingActions =>
      _pendingAction.stream;
}

enum DailyProgressReminderAction { updateProgress }

class DailyProgressReminderHost extends StatefulWidget {
  const DailyProgressReminderHost({super.key, required this.child});

  final Widget child;

  @override
  State<DailyProgressReminderHost> createState() =>
      _DailyProgressReminderHostState();
}

class _DailyProgressReminderHostState extends State<DailyProgressReminderHost>
    with WidgetsBindingObserver {
  late final DailyProgressReminderRepository _repository;
  late final DailyProgressReminderService _service;
  StreamSubscription<DailyProgressReminderAction>? _actionSub;
  bool _sheetOpen = false;
  String? _lastShownDate;

  @override
  void initState() {
    super.initState();
    _repository = GetIt.I<DailyProgressReminderRepository>();
    _service = GetIt.I<DailyProgressReminderService>();
    WidgetsBinding.instance.addObserver(this);
    _actionSub = _service.pendingActions.listen((action) {
      if (action == DailyProgressReminderAction.updateProgress && mounted) {
        AppNavigation.goIfDifferent(context, '/subjects');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actionSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  Future<void> _tick() async {
    if (!mounted) return;
    await _service.refreshSchedule();
    final pref = _repository.getPreference();
    final now = DateTime.now();
    final reminderTime = DateTime(
      now.year,
      now.month,
      now.day,
      pref.hour,
      pref.minute,
    );
    final today = _repository.todayKey();
    if (now.isBefore(reminderTime)) return;
    if (_lastShownDate == today) return;
    if (!_repository.shouldRemindToday(now: now)) return;
    _lastShownDate = today;
    await _showReminderSheet();
  }

  Future<void> _showReminderSheet() async {
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _DailyProgressReminderSheet(),
    );
    _sheetOpen = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DailyProgressReminderSheet extends StatelessWidget {
  const _DailyProgressReminderSheet();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 96,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(
                  child: Text('🔔', style: TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Daily Progress Reminder',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Looks like you haven\'t added any study progress today.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Text('💡', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Consistency is the key to success. Update your progress now!',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFEEF0),
                        foregroundColor: Colors.red.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await GetIt.I<DailyProgressReminderRepository>()
                            .markNoStudyDay();
                        await GetIt.I<DailyProgressReminderService>()
                            .cancelTodayReminder();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('😴  Didn\'t Study'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        context.go('/subjects');
                      },
                      child: const Text('🚀  Update Progress'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

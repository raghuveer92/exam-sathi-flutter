part of 'dashboard_bloc.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();
  @override
  List<Object?> get props => [];
}

class DashboardLoadRequested extends DashboardEvent {}
class DashboardRefreshRequested extends DashboardEvent {}
class DashboardResetRequested extends DashboardEvent {}

/// User tapped [+] or [-] on daily study hours — triggers instant UI update + debounced save.
class StudyHoursUpdated extends DashboardEvent {
  final double dailyTargetHours;
  const StudyHoursUpdated(this.dailyTargetHours);
  @override
  List<Object?> get props => [dailyTargetHours];
}

/// Internal — fired by the debounce timer to persist the updated hours.
class _StudyHoursSaveRequested extends DashboardEvent {
  final double hours;
  const _StudyHoursSaveRequested(this.hours);
  @override
  List<Object?> get props => [hours];
}

/// Internal — fired after 2 s to clear the "✓ Saved" indicator.
class _StudyHoursSaveStatusReset extends DashboardEvent {}

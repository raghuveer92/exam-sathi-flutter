part of 'dashboard_bloc.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();
  @override
  List<Object?> get props => [];
}

class DashboardLoadRequested extends DashboardEvent {}
class DashboardRefreshRequested extends DashboardEvent {}
class DashboardResetRequested extends DashboardEvent {}

class DashboardExamChanged extends DashboardEvent {
  final int examId;
  final String examName;
  final bool clearGoal;

  const DashboardExamChanged({
    required this.examId,
    required this.examName,
    this.clearGoal = false,
  });

  @override
  List<Object?> get props => [examId, examName, clearGoal];
}

/// Apply a locally patched user (e.g. after target date edit) without re-fetching.
class DashboardUserPatched extends DashboardEvent {
  final UserModel user;

  const DashboardUserPatched(this.user);

  @override
  List<Object?> get props => [user];
}

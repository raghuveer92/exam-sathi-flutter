part of 'dashboard_bloc.dart';

enum SaveStatus { idle, pending, saving, saved }

abstract class DashboardState extends Equatable {
  const DashboardState();
  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {}
class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final DashboardModel dashboard;
  final SaveStatus saveStatus;

  const DashboardLoaded({
    required this.dashboard,
    this.saveStatus = SaveStatus.idle,
  });

  DashboardLoaded copyWith({DashboardModel? dashboard, SaveStatus? saveStatus}) =>
      DashboardLoaded(
        dashboard: dashboard ?? this.dashboard,
        saveStatus: saveStatus ?? this.saveStatus,
      );

  @override
  List<Object?> get props => [dashboard, saveStatus];
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError({required this.message});
  @override
  List<Object?> get props => [message];
}

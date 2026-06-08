part of 'dashboard_bloc.dart';

abstract class DashboardState extends Equatable {
  const DashboardState();
  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {}
class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final DashboardModel dashboard;
  final double calculatedDailyTarget;

  const DashboardLoaded({
    required this.dashboard,
    required this.calculatedDailyTarget,
  });

  DashboardLoaded copyWith({
    DashboardModel? dashboard,
    double? calculatedDailyTarget,
  }) =>
      DashboardLoaded(
        dashboard: dashboard ?? this.dashboard,
        calculatedDailyTarget:
            calculatedDailyTarget ?? this.calculatedDailyTarget,
      );

  @override
  List<Object?> get props => [dashboard, calculatedDailyTarget];
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError({required this.message});
  @override
  List<Object?> get props => [message];
}

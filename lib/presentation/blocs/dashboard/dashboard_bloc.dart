import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/study/daily_target_calculator.dart';
import '../../../core/sync/progress_rebuild_service.dart';
import '../../../data/models/dashboard_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/dashboard_repository.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository _repository;
  final ProgressRebuildService _progressRebuildService;
  final DailyTargetCalculator _dailyTargetCalculator;

  DashboardBloc({
    required DashboardRepository repository,
    required ProgressRebuildService progressRebuildService,
    required DailyTargetCalculator dailyTargetCalculator,
  })  : _repository = repository,
        _progressRebuildService = progressRebuildService,
        _dailyTargetCalculator = dailyTargetCalculator,
        super(DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoadRequested);
    on<DashboardRefreshRequested>(_onRefreshRequested);
    on<DashboardExamChanged>(_onExamChanged);
    on<DashboardUserPatched>(_onUserPatched);
    on<DashboardResetRequested>((_, emit) => emit(DashboardInitial()));
  }

  double _calcDailyTarget(DashboardModel dashboard) =>
      _dailyTargetCalculator.calculateOverallDailyTarget(
        dashboard.myExams,
        user: dashboard.user,
      );

  void _onExamChanged(
    DashboardExamChanged event,
    Emitter<DashboardState> emit,
  ) {
    if (state is! DashboardLoaded) return;
    final current = state as DashboardLoaded;
    final updatedDashboard = current.dashboard.copyWith(
      user: current.dashboard.user.copyWith(
        selectedExamId: event.examId,
        selectedExamName: event.examName,
        clearExamDate: event.clearGoal,
        clearSyllabusTargetDate: event.clearGoal,
        clearDaysUntilExam: event.clearGoal,
      ),
    );
    emit(current.copyWith(
      dashboard: updatedDashboard,
      calculatedDailyTarget: _calcDailyTarget(updatedDashboard),
    ));
  }

  void _onUserPatched(
    DashboardUserPatched event,
    Emitter<DashboardState> emit,
  ) {
    if (state is! DashboardLoaded) return;
    final current = state as DashboardLoaded;
    final updatedDashboard = current.dashboard.copyWith(
      user: event.user,
      myExams: event.user.userExams,
    );
    emit(current.copyWith(
      dashboard: updatedDashboard,
      calculatedDailyTarget: _calcDailyTarget(updatedDashboard),
    ));
  }

  /// Local cache only — no automatic network/sync.
  Future<void> _onLoadRequested(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading());
    try {
      await _progressRebuildService.rebuildAll();
      final dashboard = await _repository.getDashboard(forceRemote: false);
      emit(DashboardLoaded(
        dashboard: dashboard,
        calculatedDailyTarget: _calcDailyTarget(dashboard),
      ));
    } catch (e) {
      emit(DashboardError(message: e.toString()));
    }
  }

  Future<void> _onRefreshRequested(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    final previousSequence =
        state is DashboardLoaded ? (state as DashboardLoaded).refreshSequence : 0;
    try {
      await _progressRebuildService.rebuildAll();
      final dashboard = await _repository.getDashboardCached();
      if (dashboard != null) {
        emit(DashboardLoaded(
          dashboard: dashboard,
          calculatedDailyTarget: _calcDailyTarget(dashboard),
          refreshSequence: previousSequence + 1,
        ));
      }
    } catch (e) {
      if (state is! DashboardLoaded) {
        emit(DashboardError(message: e.toString()));
      }
    }
  }
}

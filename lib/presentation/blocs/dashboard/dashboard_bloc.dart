import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/sync/offline_queue_service.dart';
import '../../../data/models/dashboard_model.dart';
import '../../../data/repositories/dashboard_repository.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository _repository;
  final OfflineQueueService _offlineQueue;
  Timer? _debounce;
  Timer? _resetTimer;

  DashboardBloc({
    required DashboardRepository repository,
    required OfflineQueueService offlineQueue,
  })  : _repository = repository,
        _offlineQueue = offlineQueue,
        super(DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoadRequested);
    on<DashboardRefreshRequested>(_onRefreshRequested);
    on<DashboardExamChanged>(_onExamChanged);
    on<DashboardResetRequested>((_, emit) {
      _debounce?.cancel();
      _resetTimer?.cancel();
      emit(DashboardInitial());
    });
    on<StudyHoursUpdated>(_onStudyHoursUpdated);
    on<_StudyHoursSaveRequested>(_onSaveStudyHours);
    on<_StudyHoursSaveStatusReset>((_, emit) {
      if (state is DashboardLoaded) {
        emit((state as DashboardLoaded).copyWith(saveStatus: SaveStatus.idle));
      }
    });
  }

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
    emit(current.copyWith(dashboard: updatedDashboard));
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _resetTimer?.cancel();
    return super.close();
  }

  /// Local cache only — no automatic network/sync.
  Future<void> _onLoadRequested(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading());
    try {
      final dashboard = await _repository.getDashboard(forceRemote: false);
      emit(DashboardLoaded(dashboard: dashboard));
    } catch (e) {
      emit(DashboardError(message: e.toString()));
    }
  }

  Future<void> _onRefreshRequested(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    try {
      final dashboard = await _repository.getDashboardCached();
      if (dashboard != null) {
        emit(DashboardLoaded(dashboard: dashboard));
      }
    } catch (e) {
      if (state is! DashboardLoaded) {
        emit(DashboardError(message: e.toString()));
      }
    }
  }

  void _onStudyHoursUpdated(StudyHoursUpdated event, Emitter<DashboardState> emit) {
    if (state is! DashboardLoaded) return;
    final current = state as DashboardLoaded;

    final updatedDashboard = current.dashboard.copyWith(
      user: current.dashboard.user.copyWith(
        dailyTargetHours: event.dailyTargetHours,
        weeklyTargetHours: (event.dailyTargetHours * 7 * 10).round() / 10.0,
      ),
    );
    emit(current.copyWith(dashboard: updatedDashboard, saveStatus: SaveStatus.pending));

    _debounce?.cancel();
    _resetTimer?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!isClosed) add(_StudyHoursSaveRequested(event.dailyTargetHours));
    });
  }

  Future<void> _onSaveStudyHours(
    _StudyHoursSaveRequested event,
    Emitter<DashboardState> emit,
  ) async {
    if (state is! DashboardLoaded) return;
    final current = state as DashboardLoaded;

    emit(current.copyWith(saveStatus: SaveStatus.saving));
    try {
      await _repository.updateStudyHoursLocal(event.hours);
      await _offlineQueue.enqueue(
        entityType: 'USER',
        entityId: current.dashboard.user.id.toString(),
        action: 'STUDY_HOURS',
        payload: {'dailyTargetHours': event.hours},
      );

      emit(current.copyWith(
        dashboard: current.dashboard.copyWith(
          user: current.dashboard.user.copyWith(
            dailyTargetHours: event.hours,
            weeklyTargetHours: (event.hours * 7 * 10).round() / 10.0,
          ),
        ),
        saveStatus: SaveStatus.saved,
      ));

      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (!isClosed) add(_StudyHoursSaveStatusReset());
      });
    } catch (_) {
      emit(current.copyWith(saveStatus: SaveStatus.idle));
    }
  }
}

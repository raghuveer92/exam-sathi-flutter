import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/gemini_service.dart';
import '../../../data/models/ai_notes_model.dart';

// ── States ──────────────────────────────────────────────────────────────────

abstract class AiNotesState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AiNotesInitial extends AiNotesState {}

class AiNotesLoading extends AiNotesState {
  final bool isRegenerating;
  AiNotesLoading({this.isRegenerating = false});
  @override
  List<Object?> get props => [isRegenerating];
}

class AiNotesLoaded extends AiNotesState {
  final AiNotesModel notes;
  final bool savedOffline;
  AiNotesLoaded({required this.notes, this.savedOffline = false});
  @override
  List<Object?> get props => [notes, savedOffline];
}

class AiNotesError extends AiNotesState {
  final String message;
  final bool isRateLimit;
  AiNotesError({required this.message, this.isRateLimit = false});
  @override
  List<Object?> get props => [message, isRateLimit];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class AiNotesCubit extends Cubit<AiNotesState> {
  final GeminiService _gemini;
  final SharedPreferences _prefs;

  AiNotesCubit({required GeminiService gemini, required SharedPreferences prefs})
      : _gemini = gemini,
        _prefs = prefs,
        super(AiNotesInitial());

  /// Load notes: check cache first, then generate if not cached.
  Future<void> loadNotes({
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) async {
    emit(AiNotesLoading());

    // Try cache first
    final cached = _loadFromCache(examName, subjectName, chapterName, topicName);
    if (cached != null) {
      emit(AiNotesLoaded(notes: cached, savedOffline: true));
      return;
    }

    await _generate(
      examName: examName,
      subjectName: subjectName,
      chapterName: chapterName,
      topicName: topicName,
    );
  }

  /// Force regenerate, bypassing cache.
  Future<void> regenerate({
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) async {
    emit(AiNotesLoading(isRegenerating: true));
    await _generate(
      examName: examName,
      subjectName: subjectName,
      chapterName: chapterName,
      topicName: topicName,
    );
  }

  Future<void> saveOffline() async {
    final current = state;
    if (current is! AiNotesLoaded) return;
    final notes = current.notes;
    final key = AiNotesModel.cacheKey(
      notes.examName,
      notes.subjectName,
      notes.chapterName,
      notes.topicName,
    );
    await _prefs.setString(key, notes.toCacheJson());
    emit(AiNotesLoaded(notes: notes, savedOffline: true));
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _generate({
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) async {
    try {
      final notes = await _gemini.generateNotes(
        examName: examName,
        subjectName: subjectName,
        chapterName: chapterName,
        topicName: topicName,
      );
      // Auto-cache after generation
      final key = AiNotesModel.cacheKey(examName, subjectName, chapterName, topicName);
      await _prefs.setString(key, notes.toCacheJson());
      emit(AiNotesLoaded(notes: notes, savedOffline: true));
    } on GeminiRateLimitException catch (e) {
      emit(AiNotesError(message: e.toString(), isRateLimit: true));
    } on GeminiApiException catch (e) {
      emit(AiNotesError(message: e.toString()));
    } catch (e) {
      emit(AiNotesError(message: 'Unexpected error: $e'));
    }
  }

  AiNotesModel? _loadFromCache(
    String examName,
    String subjectName,
    String chapterName,
    String topicName,
  ) {
    final key = AiNotesModel.cacheKey(examName, subjectName, chapterName, topicName);
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return AiNotesModel.fromCacheJson(raw);
    } catch (_) {
      return null;
    }
  }
}

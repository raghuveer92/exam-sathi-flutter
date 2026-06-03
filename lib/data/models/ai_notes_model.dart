import 'dart:convert';

class PracticeQuestion {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  const PracticeQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });

  factory PracticeQuestion.fromJson(Map<String, dynamic> j) => PracticeQuestion(
        question: j['question'] as String? ?? '',
        options: (j['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        correctAnswer: j['correctAnswer'] as String? ?? '',
        explanation: j['explanation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'correctAnswer': correctAnswer,
        'explanation': explanation,
      };
}

class SolvedExample {
  final String question;
  final String solution;

  const SolvedExample({required this.question, required this.solution});

  factory SolvedExample.fromJson(Map<String, dynamic> j) => SolvedExample(
        question: j['question'] as String? ?? '',
        solution: j['solution'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'question': question, 'solution': solution};
}

class AiNotesModel {
  final String examName;
  final String subjectName;
  final String chapterName;
  final String topicName;
  final String quickExplanation;
  final List<String> importantConcepts;
  final List<String> tricksAndShortcuts;
  final List<SolvedExample> solvedExamples;
  final List<PracticeQuestion> practiceQuestions;
  final List<String> commonMistakes;
  final String quickSummary;
  final DateTime generatedAt;

  const AiNotesModel({
    required this.examName,
    required this.subjectName,
    required this.chapterName,
    required this.topicName,
    required this.quickExplanation,
    required this.importantConcepts,
    required this.tricksAndShortcuts,
    required this.solvedExamples,
    required this.practiceQuestions,
    required this.commonMistakes,
    required this.quickSummary,
    required this.generatedAt,
  });

  factory AiNotesModel.fromJson(
    Map<String, dynamic> j, {
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) =>
      AiNotesModel(
        examName: examName,
        subjectName: subjectName,
        chapterName: chapterName,
        topicName: topicName,
        quickExplanation: j['quickExplanation'] as String? ?? '',
        importantConcepts: (j['importantConcepts'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        tricksAndShortcuts: (j['tricksAndShortcuts'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        solvedExamples: (j['solvedExamples'] as List<dynamic>? ?? [])
            .map((e) => SolvedExample.fromJson(e as Map<String, dynamic>))
            .toList(),
        practiceQuestions: (j['practiceQuestions'] as List<dynamic>? ?? [])
            .map((e) => PracticeQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        commonMistakes: (j['commonMistakes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        quickSummary: j['quickSummary'] as String? ?? '',
        generatedAt: DateTime.now(),
      );

  // ── Serialisation for local cache ────────────────────────────────────────

  String toCacheJson() => jsonEncode({
        'examName': examName,
        'subjectName': subjectName,
        'chapterName': chapterName,
        'topicName': topicName,
        'quickExplanation': quickExplanation,
        'importantConcepts': importantConcepts,
        'tricksAndShortcuts': tricksAndShortcuts,
        'solvedExamples': solvedExamples.map((e) => e.toJson()).toList(),
        'practiceQuestions': practiceQuestions.map((e) => e.toJson()).toList(),
        'commonMistakes': commonMistakes,
        'quickSummary': quickSummary,
        'generatedAt': generatedAt.toIso8601String(),
      });

  factory AiNotesModel.fromCacheJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return AiNotesModel(
      examName: j['examName'] as String? ?? '',
      subjectName: j['subjectName'] as String? ?? '',
      chapterName: j['chapterName'] as String? ?? '',
      topicName: j['topicName'] as String? ?? '',
      quickExplanation: j['quickExplanation'] as String? ?? '',
      importantConcepts: (j['importantConcepts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tricksAndShortcuts: (j['tricksAndShortcuts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      solvedExamples: (j['solvedExamples'] as List<dynamic>? ?? [])
          .map((e) => SolvedExample.fromJson(e as Map<String, dynamic>))
          .toList(),
      practiceQuestions: (j['practiceQuestions'] as List<dynamic>? ?? [])
          .map((e) => PracticeQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
      commonMistakes: (j['commonMistakes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      quickSummary: j['quickSummary'] as String? ?? '',
      generatedAt: DateTime.tryParse(j['generatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Cache key derived from exam/subject/chapter/topic
  static String cacheKey(String exam, String subject, String chapter, String topic) =>
      'ai_notes_${exam}_${subject}_${chapter}_$topic'
          .replaceAll(' ', '_')
          .toLowerCase();
}

class MockTestInfoModel {
  final int? id;
  final int topicId;
  final String topicTitle;
  final int numQuestions;
  final int durationMinutes;
  final int availableQuestionCount;
  final String difficultyFilter;
  final bool isActive;
  final bool sheetBacked;
  final bool? canStartFromApi;

  MockTestInfoModel({
    this.id,
    required this.topicId,
    required this.topicTitle,
    required this.numQuestions,
    required this.durationMinutes,
    required this.availableQuestionCount,
    required this.difficultyFilter,
    required this.isActive,
    this.sheetBacked = false,
    this.canStartFromApi,
  });

  factory MockTestInfoModel.fromJson(Map<String, dynamic> json) {
    return MockTestInfoModel(
      id: json['id'] as int?,
      topicId: json['topicId'] as int,
      topicTitle: json['topicTitle'] as String? ?? '',
      numQuestions: json['numQuestions'] as int? ?? 10,
      durationMinutes: json['durationMinutes'] as int? ?? 15,
      availableQuestionCount: (json['availableQuestionCount'] as num?)?.toInt() ?? 0,
      difficultyFilter: json['difficultyFilter'] as String? ?? 'ALL',
      isActive: json['isActive'] as bool? ?? false,
      sheetBacked: json['sheetBacked'] as bool? ?? false,
      canStartFromApi: json['canStart'] as bool?,
    );
  }

  bool get isConfigured => id != null || sheetBacked;

  bool get canStart =>
      canStartFromApi ??
      (isConfigured && isActive && availableQuestionCount >= numQuestions);
}

class MockTestQuestionModel {
  final int questionId;
  final String? sheetQuestionId;
  final String questionText;
  final String questionType;
  final double marks;
  final double negativeMarks;
  final List<MockTestOptionModel> options;
  final List<String> selectedOptionKeys;
  final bool markedForReview;

  MockTestQuestionModel({
    required this.questionId,
    this.sheetQuestionId,
    required this.questionText,
    required this.questionType,
    required this.marks,
    required this.negativeMarks,
    required this.options,
    this.selectedOptionKeys = const [],
    this.markedForReview = false,
  });

  bool get isMultiple => questionType.contains('MULTIPLE');

  MockTestQuestionModel copyWith({
    List<String>? selectedOptionKeys,
    bool? markedForReview,
  }) {
    return MockTestQuestionModel(
      questionId: questionId,
      sheetQuestionId: sheetQuestionId,
      questionText: questionText,
      questionType: questionType,
      marks: marks,
      negativeMarks: negativeMarks,
      options: options,
      selectedOptionKeys: selectedOptionKeys ?? this.selectedOptionKeys,
      markedForReview: markedForReview ?? this.markedForReview,
    );
  }

  factory MockTestQuestionModel.fromJson(Map<String, dynamic> json) {
    return MockTestQuestionModel(
      questionId: (json['questionId'] as num?)?.toInt() ?? 0,
      sheetQuestionId: json['sheetQuestionId'] as String?,
      questionText: json['questionText'] as String? ?? '',
      questionType: json['questionType'] as String? ?? 'SINGLE_CORRECT',
      marks: (json['marks'] as num?)?.toDouble() ?? 1,
      negativeMarks: (json['negativeMarks'] as num?)?.toDouble() ?? 0,
      options: (json['options'] as List<dynamic>? ?? [])
          .map((e) => MockTestOptionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      selectedOptionKeys: (json['selectedOptionKeys'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      markedForReview: json['markedForReview'] as bool? ?? false,
    );
  }
}

class MockTestOptionModel {
  final int id;
  final String optionKey;
  final String optionText;

  MockTestOptionModel({
    required this.id,
    required this.optionKey,
    required this.optionText,
  });

  factory MockTestOptionModel.fromJson(Map<String, dynamic> json) {
    return MockTestOptionModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      optionKey: json['optionKey'] as String? ?? '',
      optionText: json['optionText'] as String? ?? '',
    );
  }
}

class MockTestAttemptModel {
  final int id;
  final int topicId;
  final String topicTitle;
  final String status;
  final int durationMinutes;
  final int? timeSpentSeconds;
  final int totalQuestions;
  final int? correctCount;
  final int? incorrectCount;
  final int? skippedCount;
  final double? score;
  final double? maxScore;
  final double? percentage;
  final List<MockTestQuestionModel> questions;
  final List<MockTestReviewModel> review;

  MockTestAttemptModel({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.status,
    required this.durationMinutes,
    this.timeSpentSeconds,
    required this.totalQuestions,
    this.correctCount,
    this.incorrectCount,
    this.skippedCount,
    this.score,
    this.maxScore,
    this.percentage,
    this.questions = const [],
    this.review = const [],
  });

  bool get isCompleted => status != 'IN_PROGRESS';

  factory MockTestAttemptModel.fromJson(Map<String, dynamic> json) {
    return MockTestAttemptModel(
      id: (json['id'] as num).toInt(),
      topicId: (json['topicId'] as num).toInt(),
      topicTitle: json['topicTitle'] as String? ?? '',
      status: json['status'] as String? ?? 'IN_PROGRESS',
      durationMinutes: json['durationMinutes'] as int? ?? 15,
      timeSpentSeconds: json['timeSpentSeconds'] as int?,
      totalQuestions: json['totalQuestions'] as int? ?? 0,
      correctCount: json['correctCount'] as int?,
      incorrectCount: json['incorrectCount'] as int?,
      skippedCount: json['skippedCount'] as int?,
      score: (json['score'] as num?)?.toDouble(),
      maxScore: (json['maxScore'] as num?)?.toDouble(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      questions: (json['questions'] as List<dynamic>? ?? [])
          .map((e) => MockTestQuestionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      review: (json['review'] as List<dynamic>? ?? [])
          .map((e) => MockTestReviewModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MockTestReviewModel {
  final int questionId;
  final String? sheetQuestionId;
  final String questionText;
  final List<String> selectedOptionKeys;
  final List<String> correctOptionKeys;
  final String? explanation;
  final bool isCorrect;
  final double marksAwarded;

  MockTestReviewModel({
    required this.questionId,
    this.sheetQuestionId,
    required this.questionText,
    required this.selectedOptionKeys,
    required this.correctOptionKeys,
    this.explanation,
    required this.isCorrect,
    required this.marksAwarded,
  });

  factory MockTestReviewModel.fromJson(Map<String, dynamic> json) {
    return MockTestReviewModel(
      questionId: (json['questionId'] as num?)?.toInt() ?? 0,
      sheetQuestionId: json['sheetQuestionId'] as String?,
      questionText: json['questionText'] as String? ?? '',
      selectedOptionKeys: (json['selectedOptionKeys'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      correctOptionKeys: (json['correctOptionKeys'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      explanation: json['explanation'] as String?,
      isCorrect: json['isCorrect'] as bool? ?? false,
      marksAwarded: (json['marksAwarded'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MockTestPerformanceModel {
  final int totalTestsAttempted;
  final double averageScorePercent;
  final double highestScorePercent;
  final List<TopicPerformanceModel> weakTopics;
  final List<TopicPerformanceModel> strongTopics;

  MockTestPerformanceModel({
    required this.totalTestsAttempted,
    required this.averageScorePercent,
    required this.highestScorePercent,
    required this.weakTopics,
    required this.strongTopics,
  });

  factory MockTestPerformanceModel.fromJson(Map<String, dynamic> json) {
    List<TopicPerformanceModel> mapList(String key) =>
        (json[key] as List<dynamic>? ?? [])
            .map((e) => TopicPerformanceModel.fromJson(e as Map<String, dynamic>))
            .toList();

    return MockTestPerformanceModel(
      totalTestsAttempted: json['totalTestsAttempted'] as int? ?? 0,
      averageScorePercent: (json['averageScorePercent'] as num?)?.toDouble() ?? 0,
      highestScorePercent: (json['highestScorePercent'] as num?)?.toDouble() ?? 0,
      weakTopics: mapList('weakTopics'),
      strongTopics: mapList('strongTopics'),
    );
  }
}

class TopicPerformanceModel {
  final int topicId;
  final String topicTitle;
  final String subjectName;
  final double averagePercent;
  final int attemptCount;

  TopicPerformanceModel({
    required this.topicId,
    required this.topicTitle,
    required this.subjectName,
    required this.averagePercent,
    required this.attemptCount,
  });

  factory TopicPerformanceModel.fromJson(Map<String, dynamic> json) {
    return TopicPerformanceModel(
      topicId: json['topicId'] as int,
      topicTitle: json['topicTitle'] as String? ?? '',
      subjectName: json['subjectName'] as String? ?? '',
      averagePercent: (json['averagePercent'] as num?)?.toDouble() ?? 0,
      attemptCount: json['attemptCount'] as int? ?? 0,
    );
  }
}

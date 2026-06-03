import 'dart:convert';

import 'package:dio/dio.dart';

import '../../data/models/ai_notes_model.dart';

class GeminiService {
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');

  static const String _model = 'llama-3.3-70b-versatile';

  late final Dio _dio;

  GeminiService() {
    if (_apiKey.isEmpty) {
      throw const GeminiApiException(
        'AI notes are not configured. Missing GROQ_API_KEY.',
      );
    }
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.groq.com/openai/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
    _dio.options.headers['Authorization'] = 'Bearer $_apiKey';
    _dio.options.headers['Content-Type'] = 'application/json';
  }

  Future<AiNotesModel> generateNotes({
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) async {
    final prompt = _buildPrompt(
      examName: examName,
      subjectName: subjectName,
      chapterName: chapterName,
      topicName: topicName,
    );

    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': _model,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are an expert exam tutor. Always respond with valid JSON only, no markdown, no extra text.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.4,
        'max_tokens': 4096,
        'response_format': {'type': 'json_object'},
      });

      final content =
          response.data['choices'][0]['message']['content'] as String;
      if (content.isEmpty) throw const GeminiApiException('Empty response');

      final cleaned = _cleanJson(content);
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      return AiNotesModel.fromJson(
        json,
        examName: examName,
        subjectName: subjectName,
        chapterName: chapterName,
        topicName: topicName,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) throw GeminiRateLimitException();
      throw const GeminiApiException(
          'Could not generate notes. Please check your connection and try again.');
    } catch (e) {
      if (e is GeminiRateLimitException || e is GeminiApiException) rethrow;
      throw const GeminiApiException(
          'Could not generate notes. Please check your connection and try again.');
    }
  }

  String _buildPrompt({
    required String examName,
    required String subjectName,
    required String chapterName,
    required String topicName,
  }) =>
      '''
Generate comprehensive exam-oriented study notes for a student preparing for a competitive exam.

Context:
- Exam: $examName
- Subject: $subjectName
- Chapter: $chapterName
- Topic: $topicName

Return ONLY a valid JSON object with exactly this structure (no markdown, no extra text):
{
  "quickExplanation": "A clear 2-3 sentence explanation of the topic suitable for exam preparation.",
  "importantConcepts": [
    "Concept 1 with brief detail",
    "Concept 2 with brief detail",
    "Concept 3 with brief detail",
    "Concept 4 with brief detail",
    "Concept 5 with brief detail"
  ],
  "tricksAndShortcuts": [
    "Trick or shortcut 1",
    "Trick or shortcut 2",
    "Trick or shortcut 3"
  ],
  "solvedExamples": [
    {
      "question": "Example question 1",
      "solution": "Step-by-step solution with explanation"
    },
    {
      "question": "Example question 2",
      "solution": "Step-by-step solution with explanation"
    }
  ],
  "practiceQuestions": [
    {
      "question": "MCQ question 1?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswer": "Option A",
      "explanation": "Why option A is correct"
    },
    {
      "question": "MCQ question 2?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswer": "Option B",
      "explanation": "Why option B is correct"
    },
    {
      "question": "MCQ question 3?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswer": "Option C",
      "explanation": "Why option C is correct"
    }
  ],
  "commonMistakes": [
    "Common mistake 1 students make",
    "Common mistake 2 students make",
    "Common mistake 3 students make"
  ],
  "quickSummary": "A concise 2-3 sentence summary of the most important points to remember for the exam."
}
''';

  /// Strips markdown code fences if Gemini adds them despite JSON MIME type.
  String _cleanJson(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-z]*\n?'), '').replaceFirst(RegExp(r'```$'), '').trim();
    }
    return s;
  }
}

class GeminiRateLimitException implements Exception {
  @override
  String toString() => 'Rate limit exceeded. Please wait a moment and try again.';
}

class GeminiApiException implements Exception {
  final String message;
  const GeminiApiException(this.message);
  @override
  String toString() => message;
}

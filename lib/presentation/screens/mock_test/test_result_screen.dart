import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/repositories/mock_test_repository.dart';

class TestResultScreen extends StatefulWidget {
  final int topicId;
  final int attemptId;
  final MockTestAttemptModel? initialResult;

  const TestResultScreen({
    super.key,
    required this.topicId,
    required this.attemptId,
    this.initialResult,
  });

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  MockTestAttemptModel? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null || _result!.review.isEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _result = await GetIt.I<MockTestRepository>().getAttempt(widget.attemptId, review: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final r = _result!;
    return Scaffold(
      appBar: AppBar(title: Text('Result — ${r.topicTitle}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatGrid(result: r),
            const SizedBox(height: 20),
            Text('Detailed Review', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...r.review.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.questionText, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('Your answer: ${item.selectedOptionKeys.isEmpty ? 'Skipped' : item.selectedOptionKeys.join(', ')}'),
                        Text('Correct: ${item.correctOptionKeys.join(', ')}'),
                        Text('Marks: ${item.marksAwarded}',
                            style: TextStyle(color: item.isCorrect ? AppColors.success : Colors.red)),
                        if (item.explanation != null && item.explanation!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Explanation: ${item.explanation}'),
                        ],
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/mock-test/${widget.topicId}'),
                    child: const Text('Retake Test'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => context.go('/subjects'),
                    child: const Text('Back to Subjects'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final MockTestAttemptModel result;
  const _StatGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _chip('Score', '${result.score?.toStringAsFixed(1)}/${result.maxScore?.toStringAsFixed(1)}'),
        _chip('Percentage', '${result.percentage?.toStringAsFixed(1)}%'),
        _chip('Correct', '${result.correctCount}'),
        _chip('Incorrect', '${result.incorrectCount}'),
        _chip('Skipped', '${result.skippedCount}'),
        _chip('Total', '${result.totalQuestions}'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

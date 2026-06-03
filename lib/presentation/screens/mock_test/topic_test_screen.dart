import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/repositories/mock_test_repository.dart';

class TopicTestScreen extends StatefulWidget {
  final int topicId;
  final String topicTitle;

  const TopicTestScreen({
    super.key,
    required this.topicId,
    required this.topicTitle,
  });

  @override
  State<TopicTestScreen> createState() => _TopicTestScreenState();
}

class _TopicTestScreenState extends State<TopicTestScreen> {
  final _repo = GetIt.I<MockTestRepository>();
  MockTestAttemptModel? _attempt;
  List<MockTestQuestionModel> _questions = [];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  int _secondsLeft = 0;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final attempt = await _repo.startTest(widget.topicId);
      setState(() {
        _attempt = attempt;
        _questions = attempt.questions;
        _secondsLeft = attempt.durationMinutes * 60;
        _loading = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _elapsed++;
          if (_secondsLeft > 0) _secondsLeft--;
        });
        if (_secondsLeft <= 0) {
          _submit(timedOut: true);
        }
      });
    } catch (e) {
      setState(() {
        _error = _errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _submit({bool timedOut = false}) async {
    if (_attempt == null || _loading) return;
    _timer?.cancel();
    setState(() => _loading = true);
    try {
      final answers = _questions
          .map((q) => {
                'questionId': q.questionId,
                'selectedOptionKeys': q.selectedOptionKeys,
                'markedForReview': q.markedForReview,
              })
          .toList();
      final result = await _repo.submitTest(
        _attempt!.id,
        timeSpentSeconds: _elapsed,
        answers: answers,
        timedOut: timedOut,
      );
      if (!mounted) return;
      context.go(
        '/mock-test/${widget.topicId}/result/${result.id}',
        extra: result,
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleOption(MockTestQuestionModel q, String key) {
    setState(() {
      final selected = List<String>.from(q.selectedOptionKeys);
      if (q.isMultiple) {
        if (selected.contains(key)) {
          selected.remove(key);
        } else {
          selected.add(key);
        }
      } else {
        selected
          ..clear()
          ..add(key);
      }
      _questions[_currentIndex] = q.copyWith(selectedOptionKeys: selected);
    });
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    if (_attempt == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Topic Test — ${widget.topicTitle}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loading)
                  const CircularProgressIndicator()
                else ...[
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text(
                    _error ?? 'Unable to start the test.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go back'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Topic Test — ${widget.topicTitle}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No questions were loaded for this test.'),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = _questions[_currentIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text('Q${_currentIndex + 1}/${_questions.length}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _formatTime(_secondsLeft),
                style: TextStyle(
                  color: _secondsLeft < 60 ? Colors.red : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_currentIndex + 1) / _questions.length),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.questionText,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${q.marks} marks • -${q.negativeMarks} negative',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 16),
                  ...q.options.map((opt) {
                    final selected = q.selectedOptionKeys.contains(opt.optionKey);
                    return Card(
                      color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
                      child: ListTile(
                        title: Text('${opt.optionKey}. ${opt.optionText}'),
                        trailing: selected ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                        onTap: () => _toggleOption(q, opt.optionKey),
                      ),
                    );
                  }),
                  SwitchListTile(
                    title: const Text('Mark for review'),
                    value: q.markedForReview,
                    onChanged: (v) => setState(() {
                      _questions[_currentIndex] = q.copyWith(markedForReview: v);
                    }),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                  child: const Text('Previous'),
                ),
                const Spacer(),
                if (_currentIndex < _questions.length - 1)
                  ElevatedButton(
                    onPressed: () => setState(() => _currentIndex++),
                    child: const Text('Next'),
                  )
                else
                  ElevatedButton(
                    onPressed: _loading ? null : () => _submit(),
                    child: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit Test'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

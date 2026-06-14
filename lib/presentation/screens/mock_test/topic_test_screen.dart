import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../../../core/router/app_navigation.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_error_message.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/repositories/mock_test_repository.dart';
import '../../../data/repositories/progress_repository.dart';

class TopicTestScreen extends StatefulWidget {
  final int topicId;
  final String topicTitle;
  final int? subjectId;
  final int? userExamId;

  const TopicTestScreen({
    super.key,
    required this.topicId,
    required this.topicTitle,
    this.subjectId,
    this.userExamId,
  });

  @override
  State<TopicTestScreen> createState() => _TopicTestScreenState();
}

class _TopicTestScreenState extends State<TopicTestScreen> {
  static const _primary = Color(0xFF6C63FF);
  static const _primaryDark = Color(0xFF4F46E5);
  static const _softPurple = Color(0xFFF1EFFF);
  static const _screenBg = Color(0xFFFAFBFF);
  static const _border = Color(0xFFE5E7F0);

  final _repo = GetIt.I<MockTestRepository>();
  final _logger = GetIt.I<Logger>();
  MockTestAttemptModel? _attempt;
  List<MockTestQuestionModel> _questions = [];
  bool _sheetBacked = false;
  int _currentIndex = 0;
  bool _loading = true;
  bool _comingSoon = false;
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
    _logger.i(
      '[TopicTest] loading topicId=${widget.topicId} title="${widget.topicTitle}"',
    );
    try {
      final attempt = await _repo.startTest(widget.topicId);
      _sheetBacked = attempt.questions.any((q) => q.sheetQuestionId != null);
      _logger.i(
        '[TopicTest] ready topicId=${widget.topicId} attemptId=${attempt.id} '
        'questions=${attempt.questions.length} sheetBacked=$_sheetBacked',
      );
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
    } catch (e, st) {
      _logger.e(
        '[TopicTest] start failed topicId=${widget.topicId} — ${apiErrorMessage(e)}',
        error: e,
        stackTrace: st,
      );
      setState(() {
        _comingSoon = isMockTestComingSoonError(e);
        _error = mockTestUserMessage(
          e,
          fallback: 'Unable to start the test. Please try again.',
        );
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
                if (q.sheetQuestionId != null)
                  'sheetQuestionId': q.sheetQuestionId,
                if (q.questionId > 0) 'questionId': q.questionId,
                'selectedOptionKeys': q.selectedOptionKeys,
                'markedForReview': q.markedForReview,
              })
          .toList();
      final result = await _repo.submitTest(
        _attempt!.id,
        topicId: widget.topicId,
        timeSpentSeconds: _elapsed,
        answers: answers,
        timedOut: timedOut,
        sheetBacked: _sheetBacked,
      );
      final pct = result.percentage;
      if (widget.subjectId != null &&
          widget.userExamId != null &&
          pct != null) {
        await GetIt.I<ProgressRepository>().patchTopicMasteryInSubjectDetail(
          userExamId: widget.userExamId!,
          subjectId: widget.subjectId!,
          topicId: widget.topicId,
          testScore: pct,
        );
      }
      if (!mounted) return;
      AppNavigation.goIfDifferent(
        context,
        '/mock-test/${widget.topicId}/result/${result.id}',
        extra: result,
      );
    } catch (e, st) {
      _logger.e(
        '[TopicTest] submit failed topicId=${widget.topicId} — ${apiErrorMessage(e)}',
        error: e,
        stackTrace: st,
      );
      setState(() {
        _error = apiErrorMessage(e);
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

  @override
  Widget build(BuildContext context) {
    if (_attempt == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Topic Test — ${widget.topicTitle}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const CircularProgressIndicator()
                : _TestUnavailableBody(
                    comingSoon: _comingSoon,
                    message: _error ?? 'Unable to start the test.',
                    onGoBack: () => AppNavigation.pop(context),
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
            child: _TestUnavailableBody(
              comingSoon: true,
              message:
                  'Practice test for this topic is coming soon. We\'re adding questions — stay tuned!',
              onGoBack: () => AppNavigation.pop(context),
            ),
          ),
        ),
      );
    }

    final q = _questions[_currentIndex];
    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                _TestHeader(
                  current: _currentIndex + 1,
                  total: _questions.length,
                  timeText: _formatTime(_secondsLeft),
                  urgent: _secondsLeft < 60,
                  onBack: () => AppNavigation.pop(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: _QuestionCard(
                      topicTitle: widget.topicTitle,
                      question: q,
                      onToggleOption: (key) => _toggleOption(q, key),
                      onReviewChanged: (value) => setState(() {
                        _questions[_currentIndex] =
                            q.copyWith(markedForReview: value);
                      }),
                    ),
                  ),
                ),
                _BottomNav(
                  isFirst: _currentIndex == 0,
                  isLast: _currentIndex == _questions.length - 1,
                  isLoading: _loading,
                  onPrevious: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                  onNext: _currentIndex < _questions.length - 1
                      ? () => setState(() => _currentIndex++)
                      : () => _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TestHeader extends StatelessWidget {
  final int current;
  final int total;
  final String timeText;
  final bool urgent;
  final VoidCallback onBack;

  const _TestHeader({
    required this.current,
    required this.total,
    required this.timeText,
    required this.urgent,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : current / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            shadowColor: const Color(0x1A6C63FF),
            elevation: 8,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                width: 54,
                height: 54,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary,
                  size: 23,
                ),
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q$current / $total',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE7E3FF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF6C63FF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: urgent ? const Color(0xFFFFF1F2) : const Color(0xFFF1EFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    urgent ? const Color(0xFFFECACA) : const Color(0xFFE5DEFF),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F6C63FF),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: urgent ? AppColors.error : const Color(0xFF5B55EA),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  timeText,
                  style: TextStyle(
                    color: urgent ? AppColors.error : const Color(0xFF4F46E5),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String topicTitle;
  final MockTestQuestionModel question;
  final ValueChanged<String> onToggleOption;
  final ValueChanged<bool> onReviewChanged;

  const _QuestionCard({
    required this.topicTitle,
    required this.question,
    required this.onToggleOption,
    required this.onReviewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x146C63FF),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopicPill(title: topicTitle),
                const SizedBox(height: 28),
                Text(
                  question.questionText,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Choose the correct option',
                  style: TextStyle(
                    color: Color(0xFF8E8AAE),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 30),
                for (final opt in question.options) ...[
                  _OptionTile(
                    optionKey: opt.optionKey,
                    text: opt.optionText,
                    selected: question.selectedOptionKeys.contains(
                      opt.optionKey,
                    ),
                    onTap: () => onToggleOption(opt.optionKey),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE9EAF3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
            child: Row(
              children: [
                const Icon(
                  Icons.bookmark_border_rounded,
                  color: Color(0xFF7C7B9B),
                  size: 24,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Mark for review',
                    style: TextStyle(
                      color: Color(0xFF6F6D91),
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Switch(
                  value: question.markedForReview,
                  onChanged: onReviewChanged,
                  activeColor: Colors.white,
                  activeTrackColor: const Color(0xFF6C63FF),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFFC8C7D6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  final String title;

  const _TopicPill({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: _TopicTestScreenState._softPurple,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.menu_book_rounded,
            color: _TopicTestScreenState._primary,
            size: 19,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _TopicTestScreenState._primary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String optionKey;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.optionKey,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? _TopicTestScreenState._primary
                  : _TopicTestScreenState._border,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: _TopicTestScreenState._primary.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected
                      ? const LinearGradient(
                          colors: [
                            _TopicTestScreenState._primary,
                            _TopicTestScreenState._primaryDark,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : const Color(0xFFEDEAFF),
                ),
                alignment: Alignment.center,
                child: Text(
                  optionKey,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : _TopicTestScreenState._primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? _TopicTestScreenState._primary
                    : const Color(0xFFD1D3E0),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool isLoading;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;

  const _BottomNav({
    required this.isFirst,
    required this.isLast,
    required this.isLoading,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Row(
        children: [
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: isFirst ? null : onPrevious,
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
              label: const Text('Previous'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6F6D91),
                disabledForegroundColor: const Color(0xFFB7B6C8),
                side: const BorderSide(color: Color(0xFFE0E1EA)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 154,
            height: 56,
            child: FilledButton(
              onPressed: isLoading ? null : onNext,
              style: FilledButton.styleFrom(
                backgroundColor: _TopicTestScreenState._primary,
                disabledBackgroundColor: const Color(0xFFCBC7FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isLast ? 'Submit' : 'Next'),
                        const SizedBox(width: 12),
                        Icon(
                          isLast
                              ? Icons.check_rounded
                              : Icons.chevron_right_rounded,
                          size: 25,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestUnavailableBody extends StatelessWidget {
  final bool comingSoon;
  final String message;
  final VoidCallback onGoBack;

  const _TestUnavailableBody({
    required this.comingSoon,
    required this.message,
    required this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    if (comingSoon) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 36,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Coming Soon',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onGoBack,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            child: const Text('Go back'),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onGoBack,
          child: const Text('Go back'),
        ),
      ],
    );
  }
}

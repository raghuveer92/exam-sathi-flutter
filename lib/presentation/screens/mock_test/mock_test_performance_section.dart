import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/mock_test_model.dart';
import '../../../data/repositories/mock_test_repository.dart';

class MockTestPerformanceSection extends StatefulWidget {
  const MockTestPerformanceSection({super.key});

  @override
  State<MockTestPerformanceSection> createState() => _MockTestPerformanceSectionState();
}

class _MockTestPerformanceSectionState extends State<MockTestPerformanceSection> {
  MockTestPerformanceModel? _performance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = GetIt.I<MockTestRepository>();
      final cached = await repo.getPerformanceCached();
      if (cached != null && mounted) {
        setState(() => _performance = cached);
      }
      final perf = await repo.getPerformance(forceRemote: cached == null);
      if (mounted) setState(() => _performance = perf);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = _performance;
    if (p == null || p.totalTestsAttempted == 0) {
      return const Text('No mock tests attempted yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mock Test Performance', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('Tests', '${p.totalTestsAttempted}'),
            _stat('Avg Score', '${p.averageScorePercent.toStringAsFixed(1)}%'),
            _stat('Best', '${p.highestScorePercent.toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 16),
        if (p.weakTopics.isNotEmpty) ...[
          const Text('Weak Topics', style: TextStyle(fontWeight: FontWeight.w600)),
          ...p.weakTopics.map((t) => _topicRow(t, Colors.red)),
        ],
        if (p.strongTopics.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Strong Topics', style: TextStyle(fontWeight: FontWeight.w600)),
          ...p.strongTopics.map((t) => _topicRow(t, AppColors.success)),
        ],
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [Text(value, style: const TextStyle(fontWeight: FontWeight.bold)), Text(label)],
      ),
    );
  }

  Widget _topicRow(TopicPerformanceModel t, Color color) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(t.topicTitle),
      subtitle: Text('${t.subjectName} • ${t.attemptCount} attempts'),
      trailing: Text('${t.averagePercent.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

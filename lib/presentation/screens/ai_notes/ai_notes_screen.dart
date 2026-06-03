import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/ai_notes_model.dart';
import '../../blocs/ai_notes/ai_notes_cubit.dart';
import 'ai_notes_widgets.dart';

// ── Route parameters ────────────────────────────────────────────────────────

class AiNotesParams {
  final String examName;
  final String subjectName;
  final String chapterName;
  final String topicName;

  const AiNotesParams({
    required this.examName,
    required this.subjectName,
    required this.chapterName,
    required this.topicName,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AiNotesScreen extends StatelessWidget {
  final AiNotesParams params;

  const AiNotesScreen({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<AiNotesCubit>()
        ..loadNotes(
          examName: params.examName,
          subjectName: params.subjectName,
          chapterName: params.chapterName,
          topicName: params.topicName,
        ),
      child: _AiNotesView(params: params),
    );
  }
}

class _AiNotesView extends StatelessWidget {
  final AiNotesParams params;

  const _AiNotesView({required this.params});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _buildAppBar(context),
        ],
        body: BlocConsumer<AiNotesCubit, AiNotesState>(
          listener: (ctx, state) {
            if (state is AiNotesLoaded && state.savedOffline) {
              // Show a brief snackbar only after explicit save action
              // (auto-cache is silent)
            }
          },
          builder: (ctx, state) {
            if (state is AiNotesLoading) {
              return _buildLoading(state.isRegenerating);
            }
            if (state is AiNotesError) {
              return _buildError(ctx, state);
            }
            if (state is AiNotesLoaded) {
              return _buildContent(ctx, state.notes, state.savedOffline);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      stretch: true,
      backgroundColor: const Color(0xFFFF6B35),
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              params.topicName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${params.subjectName} · ${params.examName}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B35), Color(0xFFFF8C00)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.auto_awesome_rounded,
                                size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text('AI Notes',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          params.chapterName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(bool isRegenerating) {
    return Column(
      children: [
        if (isRegenerating) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Regenerating notes with AI…',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B6914),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3F0FF), Color(0xFFEDF5FF)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF6C63FF), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generating AI Notes…',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C63FF),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Gemini is crafting personalized notes for you.',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const Expanded(child: AiNotesShimmer()),
      ],
    );
  }

  Widget _buildError(BuildContext context, AiNotesError state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: state.isRateLimit
                    ? const Color(0xFFFFF3E0)
                    : const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                state.isRateLimit
                    ? Icons.hourglass_top_rounded
                    : Icons.error_outline_rounded,
                size: 40,
                color: state.isRateLimit
                    ? const Color(0xFFFF8C00)
                    : const Color(0xFFFF6B6B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              state.isRateLimit ? 'Rate Limit Reached' : 'Failed to Load Notes',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 10),
            Text(
              state.isRateLimit
                  ? 'Gemini API quota has been reached.\nPlease wait a moment and tap Retry.'
                  : 'Could not generate notes.\nPlease check your connection and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.read<AiNotesCubit>().loadNotes(
                    examName: params.examName,
                    subjectName: params.subjectName,
                    chapterName: params.chapterName,
                    topicName: params.topicName,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, AiNotesModel notes, bool savedOffline) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              // ── Quick Explanation ─────────────────────────────────────
              AiNotesSectionCard(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Quick Explanation',
                iconColor: const Color(0xFFFF8C00),
                child: Text(
                  notes.quickExplanation,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                    height: 1.6,
                  ),
                ),
              ),

              // ── Important Concepts ────────────────────────────────────
              if (notes.importantConcepts.isNotEmpty)
                AiNotesSectionCard(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'Important Concepts',
                  iconColor: const Color(0xFF6C63FF),
                  child: BulletList(
                    items: notes.importantConcepts,
                    bulletColor: const Color(0xFF6C63FF),
                  ),
                ),

              // ── Tricks & Shortcuts ────────────────────────────────────
              if (notes.tricksAndShortcuts.isNotEmpty)
                AiNotesSectionCard(
                  icon: Icons.flash_on_rounded,
                  title: 'Tricks & Shortcuts',
                  iconColor: const Color(0xFFFF6B35),
                  child: BulletList(
                    items: notes.tricksAndShortcuts,
                    bulletColor: const Color(0xFFFF6B35),
                  ),
                ),

              // ── Solved Examples ───────────────────────────────────────
              if (notes.solvedExamples.isNotEmpty)
                AiNotesSectionCard(
                  icon: Icons.calculate_outlined,
                  title: 'Solved Examples',
                  iconColor: const Color(0xFF0288D1),
                  child: Column(
                    children: notes.solvedExamples
                        .asMap()
                        .entries
                        .map((e) => SolvedExampleCard(
                              example: e.value,
                              index: e.key,
                            ))
                        .toList(),
                  ),
                ),

              // ── Practice Questions ────────────────────────────────────
              if (notes.practiceQuestions.isNotEmpty)
                AiNotesSectionCard(
                  icon: Icons.quiz_outlined,
                  title: 'Practice Questions (MCQs)',
                  iconColor: const Color(0xFF43A047),
                  child: Column(
                    children: notes.practiceQuestions
                        .asMap()
                        .entries
                        .map((e) => PracticeQuestionCard(
                              key: ValueKey('q_${e.key}'),
                              question: e.value,
                              index: e.key,
                            ))
                        .toList(),
                  ),
                ),

              // ── Common Mistakes ───────────────────────────────────────
              if (notes.commonMistakes.isNotEmpty)
                AiNotesSectionCard(
                  icon: Icons.warning_amber_rounded,
                  title: 'Common Mistakes',
                  iconColor: const Color(0xFFE53935),
                  child: BulletList(
                    items: notes.commonMistakes,
                    bulletColor: const Color(0xFFE53935),
                  ),
                ),

              // ── Quick Summary ─────────────────────────────────────────
              AiNotesSectionCard(
                icon: Icons.summarize_outlined,
                title: 'Quick Summary',
                iconColor: const Color(0xFF00897B),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    notes.quickSummary,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF00695C),
                      height: 1.6,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),

              // Generated at
              Text(
                'Generated by Gemini AI · ${_formatDate(notes.generatedAt)}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFADB5BD)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // ── Floating action buttons ───────────────────────────────────
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Regenerate',
                  color: const Color(0xFF6C63FF),
                  onTap: () => context.read<AiNotesCubit>().regenerate(
                        examName: params.examName,
                        subjectName: params.subjectName,
                        chapterName: params.chapterName,
                        topicName: params.topicName,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: savedOffline
                      ? Icons.check_circle_rounded
                      : Icons.download_rounded,
                  label: savedOffline ? 'Saved Offline' : 'Save Offline',
                  color: savedOffline
                      ? const Color(0xFF43A047)
                      : const Color(0xFF0288D1),
                  onTap: savedOffline
                      ? null
                      : () => context.read<AiNotesCubit>().saveOffline(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      shadowColor: color.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

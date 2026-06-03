import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../data/models/ai_notes_model.dart';

// ─── Section Card ─────────────────────────────────────────────────────────────

class AiNotesSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;
  final Widget child;

  const AiNotesSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─── Bullet List ──────────────────────────────────────────────────────────────

class BulletList extends StatelessWidget {
  final List<String> items;
  final Color bulletColor;

  const BulletList({
    super.key,
    required this.items,
    required this.bulletColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 6, right: 10),
                decoration: BoxDecoration(
                  color: bulletColor,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  e.value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Solved Example Card ──────────────────────────────────────────────────────

class SolvedExampleCard extends StatelessWidget {
  final SolvedExample example;
  final int index;

  const SolvedExampleCard({
    super.key,
    required this.example,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Example ${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            example.question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              example.solution,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Practice Question Card ───────────────────────────────────────────────────

class PracticeQuestionCard extends StatefulWidget {
  final PracticeQuestion question;
  final int index;

  const PracticeQuestionCard({
    super.key,
    required this.question,
    required this.index,
  });

  @override
  State<PracticeQuestionCard> createState() => _PracticeQuestionCardState();
}

class _PracticeQuestionCardState extends State<PracticeQuestionCard> {
  String? _selectedAnswer;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF43A047).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Q${widget.index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF43A047),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.question.question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.question.options.map((opt) {
            final isSelected = _selectedAnswer == opt;
            final isCorrect = opt == widget.question.correctAnswer;
            Color optionBg = Colors.white;
            Color borderColor = Colors.grey.shade300;
            Color textColor = const Color(0xFF374151);

            if (_revealed) {
              if (isCorrect) {
                optionBg = const Color(0xFFE8F5E9);
                borderColor = const Color(0xFF43A047);
                textColor = const Color(0xFF2E7D32);
              } else if (isSelected && !isCorrect) {
                optionBg = const Color(0xFFFFEBEE);
                borderColor = const Color(0xFFE53935);
                textColor = const Color(0xFFB71C1C);
              }
            } else if (isSelected) {
              optionBg = const Color(0xFFF3F0FF);
              borderColor = const Color(0xFF6C63FF);
              textColor = const Color(0xFF6C63FF);
            }

            return GestureDetector(
              onTap: _revealed ? null : () => setState(() => _selectedAnswer = opt),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: optionBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          fontWeight: isCorrect && _revealed
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (_revealed && isCorrect)
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF43A047), size: 16),
                    if (_revealed && isSelected && !isCorrect)
                      const Icon(Icons.cancel_rounded,
                          color: Color(0xFFE53935), size: 16),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          if (!_revealed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _selectedAnswer == null
                    ? null
                    : () => setState(() => _revealed = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _selectedAnswer == null
                        ? Colors.grey.shade300
                        : const Color(0xFF43A047),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  'Check Answer',
                  style: TextStyle(
                    color: _selectedAnswer == null
                        ? Colors.grey.shade400
                        : const Color(0xFF43A047),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 15, color: Color(0xFF43A047)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.question.explanation,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF374151),
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shimmer Loading ──────────────────────────────────────────────────────────

class AiNotesShimmer extends StatelessWidget {
  const AiNotesShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8EBF5),
      highlightColor: const Color(0xFFF5F7FF),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            5,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _shimmerBox(36, 36, radius: 10),
                    const SizedBox(width: 12),
                    _shimmerBox(16, 120),
                  ]),
                  const SizedBox(height: 16),
                  _shimmerBox(14, double.infinity),
                  const SizedBox(height: 8),
                  _shimmerBox(14, double.infinity),
                  const SizedBox(height: 8),
                  _shimmerBox(14, 200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox(double h, double w, {double radius = 6}) => Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

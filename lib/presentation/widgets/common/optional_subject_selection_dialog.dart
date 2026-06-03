import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/exam_subject_group_model.dart';

Future<List<Map<String, dynamic>>?> showOptionalSubjectSelectionDialog({
  required BuildContext context,
  required String examName,
  required List<ExamSubjectGroupModel> groups,
}) async {
  final optionalGroups = groups.where((group) => group.isOptional).toList();
  if (optionalGroups.isEmpty) {
    return const [];
  }

  final selectedByGroup = {
    for (final group in optionalGroups)
      group.id: group.subjects.where((subject) => subject.selected).map((subject) => subject.id).toSet(),
  };

  bool isValid() {
    for (final group in optionalGroups) {
      final selected = selectedByGroup[group.id] ?? <int>{};
      if (selected.length < group.minSelection) {
        return false;
      }
      if (group.maxSelection > 0 && selected.length > group.maxSelection) {
        return false;
      }
    }
    return true;
  }

  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          void toggleSelection(ExamSubjectGroupModel group, int subjectId, bool nextValue) {
            final current = selectedByGroup[group.id] ?? <int>{};
            if (group.maxSelection == 1) {
              selectedByGroup[group.id] = nextValue ? {subjectId} : <int>{};
              setState(() {});
              return;
            }

            final next = <int>{...current};
            if (nextValue) {
              if (group.maxSelection > 0 && next.length >= group.maxSelection) {
                return;
              }
              next.add(subjectId);
            } else {
              next.remove(subjectId);
            }
            selectedByGroup[group.id] = next;
            setState(() {});
          }

          return AlertDialog(
            title: Text('Choose Optional Subjects for $examName'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final group in optionalGroups) ...[
                      Text(
                        group.groupName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        group.maxSelection == 1
                            ? 'Select ${group.minSelection == 0 ? 'up to 1' : '1'} subject'
                            : 'Select ${group.minSelection} to ${group.maxSelection} subjects',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ...group.subjects.map((subject) {
                        final selected = selectedByGroup[group.id]?.contains(subject.id) ?? false;
                        if (group.maxSelection == 1) {
                          return RadioListTile<int>(
                            value: subject.id,
                            groupValue: selectedByGroup[group.id]?.cast<int?>().firstOrNull,
                            onChanged: (_) => toggleSelection(group, subject.id, true),
                            title: Text(subject.name),
                            contentPadding: EdgeInsets.zero,
                          );
                        }
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (value) => toggleSelection(group, subject.id, value ?? false),
                          title: Text(subject.name),
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                      if ((selectedByGroup[group.id]?.length ?? 0) < group.minSelection)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 12),
                          child: Text(
                            'Please select at least ${group.minSelection} subject(s).',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                      const Divider(height: 24),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isValid()
                    ? () => Navigator.of(dialogContext).pop([
                          for (final group in optionalGroups)
                            {
                              'groupId': group.id,
                              'subjectIds': (selectedByGroup[group.id] ?? <int>{}).toList(),
                            },
                        ])
                    : null,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    },
  );
}
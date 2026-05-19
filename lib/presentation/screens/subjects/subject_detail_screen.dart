import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';

class SubjectDetailScreen extends StatelessWidget {
  final int subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chapters')),
      body: Center(
        child: Text('Subject $subjectId — Chapter list'),
      ),
    );
  }
}

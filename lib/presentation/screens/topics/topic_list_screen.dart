import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class TopicListScreen extends StatelessWidget {
  final int chapterId;
  const TopicListScreen({super.key, required this.chapterId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Topics')),
      body: Center(
        child: Text('Chapter $chapterId — Topic list'),
      ),
    );
  }
}

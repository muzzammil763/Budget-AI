import 'package:flutter/material.dart';
import 'package:budget_ai/features/changes/data/file_change.dart';

class ChangesDiffScreen extends StatelessWidget {
  final List<FileChange> changes;

  const ChangesDiffScreen({super.key, this.changes = const []});

  static void open(BuildContext context, List<FileChange> changes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangesDiffScreen(changes: changes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Not available')));
}

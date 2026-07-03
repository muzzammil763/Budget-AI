import 'package:flutter/material.dart';

class GithubFileViewerScreen extends StatelessWidget {
  final String? filePath;
  final bool? isLocalFile;
  final String? localPath;
  final String? fullName;
  final String? branch;

  const GithubFileViewerScreen({
    super.key,
    this.filePath,
    this.isLocalFile,
    this.localPath,
    this.fullName,
    this.branch,
  });

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Not available')));
}

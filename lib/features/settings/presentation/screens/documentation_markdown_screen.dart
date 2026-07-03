import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_response_markdown.dart';
import 'package:budget_ai/generated/documentation_data.dart';

class DocumentationMarkdownScreen extends StatelessWidget {
  final String title;
  final String markdown;

  const DocumentationMarkdownScreen({
    super.key,
    required this.title,
    required this.markdown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: Text(title),
      ),
      body: markdown.trim().isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No content available for $title',
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                RepaintBoundary(
                  child: ChatResponseMarkdown(
                    text: markdown.trim(),
                    isStreaming: false,
                    onLinkTap: (_, _) async {},
                  ),
                ),
              ],
            ),
    );
  }
}

class AgentsMarkdownScreen extends StatelessWidget {
  const AgentsMarkdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentationMarkdownScreen(
      title: 'AGENTS.md',
      markdown: appAgentsMarkdown,
    );
  }
}

class ReadmeMarkdownScreen extends StatelessWidget {
  const ReadmeMarkdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentationMarkdownScreen(
      title: 'README.md',
      markdown: appReadmeMarkdown,
    );
  }
}

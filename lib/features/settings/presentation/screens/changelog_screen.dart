import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/features/chat/presentation/widgets/chat_response_markdown.dart';
import 'package:budget_ai/generated/changelog_data.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  static final List<String> _sections = _parseSections(appChangelogMarkdown);
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  static List<String> _parseSections(String markdown) {
    final normalized = markdown.trim();
    if (normalized.isEmpty) return const [];

    final withoutTitle = normalized.replaceFirst(
      RegExp(r'^#\s+Changelog\s*', caseSensitive: false),
      '',
    );
    final matches = RegExp(r'^##\s+', multiLine: true).allMatches(withoutTitle);
    if (matches.isEmpty) return [withoutTitle.trim()];

    final starts = matches.map((match) => match.start).toList();
    return [
      for (var i = 0; i < starts.length; i += 1)
        withoutTitle
            .substring(
              starts[i],
              i + 1 < starts.length ? starts[i + 1] : withoutTitle.length,
            )
            .trim(),
    ].where((section) => section.isNotEmpty).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Changelogs'),
        actions: [
          FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snapshot) {
              final info = snapshot.data;
              if (info == null) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${info.version} (${info.buildNumber})',
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _sections.isEmpty
          ? Center(
              child: Text(
                'No changelog entries yet',
                style: AppTheme.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _sections.length,
              scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
              itemBuilder: (context, index) {
                final section = _sections[index];
                return KeyedSubtree(
                  key: ValueKey(section.hashCode),
                  child: _ChangelogSectionCard(text: section),
                );
              },
            ),
    );
  }
}

class _ChangelogSectionCard extends StatelessWidget {
  final String text;

  const _ChangelogSectionCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ChatResponseMarkdown(
          text: text,
          isStreaming: false,
          onLinkTap: (_, _) async {},
        ),
      ),
    );
  }
}

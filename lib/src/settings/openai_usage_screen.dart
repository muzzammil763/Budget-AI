import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/settings/openai_usage_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class OpenAIUsageScreen extends StatelessWidget {
  const OpenAIUsageScreen({super.key});

  String _number(num value) {
    final digits = value.round().toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  String _duration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} sec';
    }
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(minutes < 10 ? 1 : 0)} min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OpenAI usage')),
      body: ValueListenableBuilder<OpenAIUsageSnapshot>(
        valueListenable: OpenAIUsageService.instance.usage,
        builder: (context, usage, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _notice(context, usage),
            const SizedBox(height: 12),
            _section(
              context,
              title: 'AI responses',
              icon: CupertinoIcons.sparkles,
              values: [
                ('Requests', _number(usage.responseRequests)),
                ('Input tokens', _number(usage.inputTokens)),
                ('Cached input', _number(usage.cachedInputTokens)),
                ('Output tokens', _number(usage.outputTokens)),
                ('Reasoning tokens', _number(usage.reasoningTokens)),
                ('Total tokens', _number(usage.totalTokens)),
              ],
            ),
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Voice input',
              icon: CupertinoIcons.mic_fill,
              values: [
                ('Transcriptions', _number(usage.transcriptionRequests)),
                ('Audio processed', _duration(usage.transcriptionSeconds)),
              ],
            ),
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Spoken replies',
              icon: CupertinoIcons.speaker_2_fill,
              values: [
                ('Speech requests', _number(usage.speechRequests)),
                ('Characters', _number(usage.speechCharacters)),
              ],
            ),
            if (usage.byModel.isNotEmpty) ...[
              const SizedBox(height: 10),
              _section(
                context,
                title: 'Requests by model',
                icon: CupertinoIcons.square_stack_3d_up_fill,
                values: usage.byModel.entries
                    .map((entry) => (entry.key, _number(entry.value)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: usage.isEmpty ? null : () => _confirmReset(context),
              icon: const Icon(CupertinoIcons.delete),
              label: const Text('Reset local usage'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, OpenAIUsageSnapshot usage) {
    final theme = Theme.of(context);
    final since = usage.trackingSince?.toLocal();
    final sinceText = since == null
        ? 'Tracking starts with the next successful request.'
        : 'Tracked on this installation since ${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        '$sinceText This is app-local activity, not an invoice total. OpenAI’s authoritative organization usage and costs require a privileged Admin key, which should never be embedded in this app.',
        style: AppTheme.bodySmall.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<(String, String)> values,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < values.length; index++) ...[
            if (index > 0) const Divider(height: 12),
            Row(
              children: [
                Expanded(child: Text(values[index].$1)),
                Text(
                  values[index].$2,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset local usage?'),
        content: const Text(
          'This clears only the counters stored on this device. It does not change OpenAI billing records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await OpenAIUsageService.instance.reset();
  }
}

import 'package:budget_ai/src/helpers/app_button.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';

enum AiReportReason {
  inaccurate('Inaccurate or wrong', 'Wrong amounts, categories, or facts'),
  harmful('Harmful or unsafe', 'Advice that could cause harm'),
  inappropriate('Offensive or inappropriate', 'Rude, hateful, or explicit'),
  other('Something else', 'Tell us in the note below');

  const AiReportReason(this.label, this.hint);

  final String label;
  final String hint;
}

/// Sends a user's report about one AI reply to the `ai_reports` table.
class AiReportService {
  AiReportService._();

  static const _maxReplyLength = 8000;

  static Future<void> submit({
    required AiReportReason reason,
    required String note,
    required String replyText,
    String? modelId,
  }) async {
    final info = await PackageInfo.fromPlatform();
    final reply = replyText.trim();
    await Supabase.instance.client.from('ai_reports').insert({
      'reason': reason.name,
      'note': note.trim(),
      'reply_text': reply.length > _maxReplyLength
          ? reply.substring(0, _maxReplyLength)
          : reply,
      'model_id': modelId,
      'app_version': '${info.version}+${info.buildNumber}',
    });
  }

  static Future<void> show(
    BuildContext context, {
    required String replyText,
    String? modelId,
  }) {
    final theme = Theme.of(context);
    return ResponsiveInfoSheet.show<void>(
      context,
      title: 'Report this reply',
      headerIcon: Icon(
        CupertinoIcons.flag,
        size: 28,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [_ReportForm(replyText: replyText, modelId: modelId)],
    );
  }
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({required this.replyText, this.modelId});

  final String replyText;
  final String? modelId;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final _note = TextEditingController();
  AiReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    try {
      await AiReportService.submit(
        reason: reason,
        note: _note.text,
        replyText: widget.replyText,
        modelId: widget.modelId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppToast(
        context,
        message: 'Thanks. Your report was sent for review.',
        type: ToastificationType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppToast(
        context,
        message: 'Could not send the report. Check your connection.',
        type: ToastificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is wrong with this reply?',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final reason in AiReportReason.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReasonTile(
                reason: reason,
                selected: _reason == reason,
                onTap: _sending ? null : () => setState(() => _reason = reason),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('ai-report-note'),
            controller: _note,
            enabled: !_sending,
            maxLines: 3,
            minLines: 2,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add details (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This reply and your note are sent to Budget AI for review. '
            'Nothing else from your chat is shared.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            key: const ValueKey('ai-report-send'),
            text: 'Send report',
            icon: CupertinoIcons.paperplane,
            isLoading: _sending,
            onPressed: _reason == null ? null : _send,
            disabledMessage: 'Choose what is wrong first.',
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final AiReportReason reason;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.4),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason.label,
                    style: AppTheme.bodyMedium.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    reason.hint,
                    style: AppTheme.bodySmall.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy and Report actions shown under a finished AI reply.
class AiReplyActions extends StatelessWidget {
  const AiReplyActions({
    super.key,
    required this.replyText,
    required this.onCopy,
    this.modelId,
  });

  final String replyText;
  final VoidCallback onCopy;
  final String? modelId;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18, color: color),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        children: [
          action(CupertinoIcons.doc_on_doc, 'Copy reply', () {
            onCopy();
            showAppToast(context, message: 'Reply copied');
          }),
          action(
            CupertinoIcons.flag,
            'Report reply',
            () => AiReportService.show(
              context,
              replyText: replyText,
              modelId: modelId,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared "save this recovery key" step used by both the first-time
/// encryption setup flow and the lost-key reset flow. The key is shown
/// once; the user must copy it before the confirmation checkbox unlocks,
/// and Continue stays disabled until that checkbox is ticked.
class RecoveryKeyPanel extends StatefulWidget {
  const RecoveryKeyPanel({
    super.key,
    required this.recoveryKey,
    required this.onContinue,
    this.continueLabel = 'Continue',
  });

  final String recoveryKey;
  final VoidCallback onContinue;
  final String continueLabel;

  @override
  State<RecoveryKeyPanel> createState() => _RecoveryKeyPanelState();
}

class _RecoveryKeyPanelState extends State<RecoveryKeyPanel> {
  bool _copied = false;
  bool _confirmed = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (!mounted) return;
    setState(() => _copied = true);
    showAppToast(context, message: 'Recovery key copied.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your recovery key', style: AppTheme.headingSmall),
              const SizedBox(height: 8),
              Text(
                'You need this to unlock your finance data on another '
                'device. We cannot recover it for you if it is lost.',
                style: AppTheme.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                widget.recoveryKey,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: Icon(
                  _copied ? CupertinoIcons.checkmark_alt : CupertinoIcons.doc_on_doc,
                ),
                label: Text(_copied ? 'Copied' : 'Copy recovery key'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        CheckboxListTile(
          value: _confirmed,
          onChanged: _copied
              ? (value) => setState(() => _confirmed = value ?? false)
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            "I've saved this somewhere safe",
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: _copied
              ? null
              : Text(
                  'Copy the key above first',
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _confirmed ? widget.onContinue : null,
          child: Text(widget.continueLabel),
        ),
      ],
    );
  }
}

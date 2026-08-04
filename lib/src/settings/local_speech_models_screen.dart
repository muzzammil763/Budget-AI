import 'dart:async';

import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class LocalSpeechModelsScreen extends StatefulWidget {
  const LocalSpeechModelsScreen({super.key});

  @override
  State<LocalSpeechModelsScreen> createState() =>
      _LocalSpeechModelsScreenState();
}

class _LocalSpeechModelsScreenState extends State<LocalSpeechModelsScreen> {
  @override
  Widget build(BuildContext context) {
    final manager = LocalSpeechModelManager.instance;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Offline Speech Models'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child:
                ValueListenableBuilder<Map<String, LocalSpeechDownloadState>>(
                  valueListenable: manager.states,
                  builder: (context, states, _) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _privacyCard(context),
                      const SizedBox(height: 8),
                      _sectionTitle(context, 'Speech To Text'),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          for (final model in LocalSpeechModels.ofKind(
                            LocalSpeechModelKind.speechToText,
                          ))
                            _modelCard(context, model, states[model.id]),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Widget _privacyCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.lock_shield_fill, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Microphone audio stays on this device. Only the transcribed '
              'text is sent to OpenAI for chat.',
              style: AppTheme.bodySmall.copyWith(
                color: colors.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: AppTheme.bodyMedium.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _modelCard(
    BuildContext context,
    LocalSpeechModel model,
    LocalSpeechDownloadState? state,
  ) {
    final colors = Theme.of(context).colorScheme;
    final installed = state?.installed ?? false;
    final downloading = state?.downloading ?? false;
    final card = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colors.outline.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: AppTheme.bodyMedium.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          model.description,
                          style: AppTheme.bodySmall.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!installed && !downloading) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => _download(context, model),
                      child: const Text('Download'),
                    ),
                  ] else if (installed) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Downloaded',
                      style: AppTheme.bodySmall.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'MODEL DETAILS',
                style: AppTheme.bodySmall.copyWith(
                  color: colors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              for (final detail in model.details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: AppTheme.bodySmall.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          detail,
                          style: AppTheme.bodySmall.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (downloading) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      end: (state?.progress ?? 0).clamp(0.0, 1.0),
                    ),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.linear,
                    builder: (context, animatedProgress, _) =>
                        LinearProgressIndicator(
                          value: animatedProgress,
                          minHeight: 8,
                          color: colors.primary,
                          backgroundColor: colors.primary.withValues(
                            alpha: 0.12,
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _downloadStatus(state),
                  style: AppTheme.bodySmall.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
              if (state?.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state!.error!,
                  style: AppTheme.bodySmall.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!installed) return card;

    return Dismissible(
      key: ValueKey('installed-speech-model-${model.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(colors),
      confirmDismiss: (_) => _confirmRemove(context, model),
      onDismissed: (_) => unawaited(_removeModel(context, model)),
      child: card,
    );
  }

  String _downloadStatus(LocalSpeechDownloadState? state) {
    if (state?.installing ?? false) return 'Installing model…';
    if (state == null) return 'Preparing download…';

    final details = <String>[
      if (state.progress != null)
        '${(state.progress! * 100).clamp(0, 100).round()}%',
      if (state.totalBytes != null)
        '${_formatBytes(state.receivedBytes)} of '
            '${_formatBytes(state.totalBytes!)}',
      if (state.bytesPerSecond > 0)
        '${_formatBytes(state.bytesPerSecond.round())}/s',
      if (state.remainingSeconds != null && state.remainingSeconds! > 0)
        '${_formatRemaining(state.remainingSeconds!)} remaining',
    ];
    return details.isEmpty ? 'Preparing download…' : details.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000000) {
      return '${(bytes / 1000).toStringAsFixed(1)} KB';
    }
    if (bytes < 1000000000) {
      return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
  }

  String _formatRemaining(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds == 0
          ? '${minutes}m'
          : '${minutes}m ${remainingSeconds}s';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}m';
  }

  Widget _deleteBackground(ColorScheme colors) {
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Icon(CupertinoIcons.trash, color: colors.error),
    );
  }

  Future<void> _download(BuildContext context, LocalSpeechModel model) async {
    try {
      await LocalSpeechModelManager.instance.download(model);
      if (!context.mounted) return;
      showAppToast(
        context,
        message: '${model.name} is downloaded.',
        type: ToastificationType.success,
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: 'Could not download ${model.name}.',
        type: ToastificationType.error,
      );
    }
  }

  Future<bool> _confirmRemove(
    BuildContext context,
    LocalSpeechModel model,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await ResponsiveInfoSheet.show<bool>(
      context,
      title: 'Remove Offline Model?',
      headerIcon: Icon(
        CupertinoIcons.trash,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.error),
      ),
      gradientColors: [
        theme.colorScheme.error,
        theme.colorScheme.error.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Remove "${model.name}" from this device? You can download it '
          'again whenever you need it.',
          style: AppTheme.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Remove',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    if (confirmed != true) return false;
    return true;
  }

  Future<void> _removeModel(
    BuildContext context,
    LocalSpeechModel model,
  ) async {
    try {
      await LocalSpeechModelManager.instance.delete(model);
      if (!context.mounted) return;
      showAppToast(
        context,
        message: '${model.name} removed.',
        type: ToastificationType.success,
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: 'Could not remove ${model.name}.',
        type: ToastificationType.error,
      );
    }
  }
}

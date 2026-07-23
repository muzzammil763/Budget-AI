import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/speech/local_speech_model.dart';
import 'package:budget_ai/src/speech/local_speech_model_manager.dart';
import 'package:budget_ai/src/speech/local_speech_service.dart';
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
  static const _previewText =
      'Hello, this is how I will sound when reading your Budget AI replies.';

  final AudioPlayer _previewPlayer = AudioPlayer();
  final LocalSpeechService _speechService = LocalSpeechService();
  StreamSubscription<void>? _previewCompletionSubscription;
  String? _loadingPreviewId;
  String? _playingPreviewId;

  @override
  void initState() {
    super.initState();
    _previewCompletionSubscription = _previewPlayer.onPlayerComplete.listen((
      _,
    ) {
      if (!mounted) return;
      setState(() => _playingPreviewId = null);
    });
  }

  @override
  void dispose() {
    _previewCompletionSubscription?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = LocalSpeechModelManager.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Speech Models')),
      body: ValueListenableBuilder<Map<String, LocalSpeechDownloadState>>(
        valueListenable: manager.states,
        builder: (context, states, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _privacyCard(context),
            const SizedBox(height: 8),
            _sectionTitle(context, 'Speech To Text'),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: manager.selectedSttId,
              builder: (context, selected, _) => Column(
                children: [
                  for (final model in LocalSpeechModels.ofKind(
                    LocalSpeechModelKind.speechToText,
                  ))
                    _modelCard(context, model, states[model.id], selected),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle(context, 'Text To Speech'),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: manager.selectedTtsId,
              builder: (context, selected, _) => Column(
                children: [
                  for (final model in LocalSpeechModels.ofKind(
                    LocalSpeechModelKind.textToSpeech,
                  ))
                    _modelCard(context, model, states[model.id], selected),
                ],
              ),
            ),
          ],
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
              'Microphone audio and spoken replies stay on this device. '
              'Only the transcribed text is sent to OpenAI for chat.',
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
    String selectedId,
  ) {
    final colors = Theme.of(context).colorScheme;
    final installed = state?.installed ?? false;
    final selected = installed && selectedId == model.id;
    final downloading = state?.downloading ?? false;
    final card = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? colors.primary
                : colors.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: installed && !selected ? () => _select(context, model) : null,
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
                            '${model.description} · '
                            '${model.installedSizeLabel}',
                            style: AppTheme.bodySmall.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (installed &&
                        model.kind == LocalSpeechModelKind.textToSpeech) ...[
                      const SizedBox(width: 8),
                      _previewButton(colors, model),
                    ],
                    if (!installed && !downloading) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => _download(context, model),
                        child: const Text('Download'),
                      ),
                    ],
                  ],
                ),
                if (downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: state?.progress),
                  const SizedBox(height: 6),
                  Text(
                    state?.progress == null
                        ? 'Downloading…'
                        : 'Downloading ${(state!.progress! * 100).round()}%',
                    style: AppTheme.bodySmall.copyWith(
                      color: colors.onSurfaceVariant,
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

  Widget _previewButton(ColorScheme colors, LocalSpeechModel model) {
    final loading = _loadingPreviewId == model.id;
    final playing = _playingPreviewId == model.id;
    return SizedBox.square(
      dimension: 40,
      child: loading
          ? const Center(
              child: SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          : IconButton(
              tooltip: playing ? 'Stop voice preview' : 'Play voice preview',
              onPressed: () => _togglePreview(model),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: colors.primary,
              ),
              icon: Icon(
                playing ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                size: 24,
              ),
            ),
    );
  }

  Widget _deleteBackground(ColorScheme colors) {
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: Icon(CupertinoIcons.trash, color: colors.error),
    );
  }

  Future<void> _download(BuildContext context, LocalSpeechModel model) async {
    try {
      await LocalSpeechModelManager.instance.download(model);
      if (!context.mounted) return;
      showAppToast(
        context,
        message: '${model.name} is downloaded and selected.',
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

  Future<void> _select(BuildContext context, LocalSpeechModel model) async {
    await LocalSpeechModelManager.instance.select(model);
    if (!context.mounted) return;
    showAppToast(
      context,
      message: '${model.name} selected.',
      type: ToastificationType.success,
    );
  }

  Future<void> _togglePreview(LocalSpeechModel model) async {
    if (_loadingPreviewId == model.id || _playingPreviewId == model.id) {
      await _previewPlayer.stop();
      if (mounted) {
        setState(() {
          _loadingPreviewId = null;
          _playingPreviewId = null;
        });
      }
      return;
    }

    await _previewPlayer.stop();
    if (!mounted) return;
    setState(() {
      _loadingPreviewId = model.id;
      _playingPreviewId = null;
    });
    try {
      final audio = await _speechService.synthesize(
        _previewText,
        modelId: model.id,
      );
      if (!mounted || _loadingPreviewId != model.id) return;
      await _previewPlayer.play(BytesSource(audio, mimeType: 'audio/wav'));
      if (!mounted || _loadingPreviewId != model.id) return;
      setState(() {
        _loadingPreviewId = null;
        _playingPreviewId = model.id;
      });
    } catch (_) {
      if (!mounted || _loadingPreviewId != model.id) return;
      setState(() {
        _loadingPreviewId = null;
        _playingPreviewId = null;
      });
      showAppToast(
        context,
        message: 'Could not play the ${model.name} preview.',
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
    if (_loadingPreviewId == model.id || _playingPreviewId == model.id) {
      await _previewPlayer.stop();
      if (mounted) {
        setState(() {
          _loadingPreviewId = null;
          _playingPreviewId = null;
        });
      }
    }
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

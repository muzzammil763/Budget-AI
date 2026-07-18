import 'dart:async';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:budget_ai/src/chat/elevenlabs_audio_service.dart';
import 'package:budget_ai/src/chat/groq_audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/finances/finance_insights_screen.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/onboarding/onboarding_screen.dart';
import 'package:budget_ai/src/settings/app_backup_service.dart';
import 'package:budget_ai/src/settings/currency_picker_screen.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:budget_ai/src/chat/ai_models.dart';
import 'package:budget_ai/src/chat/model_picker_sheet.dart';
import 'package:budget_ai/src/chat/user_bubble_style_surface.dart';
import 'package:budget_ai/src/settings/bubble_style_settings_service.dart';
import 'package:budget_ai/src/settings/permissions_screen.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toastification/toastification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
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
        actions: [
          if (_packageInfo != null) ...[
            Text(
              '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          const _SettingsNameEditor(),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.money_dollar_circle,
            title: 'Finances',
            subtitle: 'View and manage finances data',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancesScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            leading: const BudgetMarkIcon(size: 30),
            title: 'Finance Insights',
            subtitle: 'Overall and monthly spending insights',
            onTap: _openInsights,
          ),
          ValueListenableBuilder<String>(
            valueListenable: CurrencySettingsService.instance.currency,
            builder: (context, currency, _) {
              return _buildNavTile(
                theme,
                leading: _buildCurrencyLeading(theme, currency),
                title: 'Currency display',
                subtitle:
                    'Amounts display as ${CurrencySettingsService.instance.formatAmount(1200)} using $currency',
                onTap: _showCurrencyScreen,
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: ModelSettingsService.instance.modelId,
            builder: (context, modelId, _) {
              final model = AIModels.getModelById(modelId);
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.sparkles,
                title: 'AI Model',
                subtitle: model?.name ?? modelId,
                onTap: _showModelSheet,
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: ModelSettingsService.instance.speechProviderId,
            builder: (context, speechProviderId, _) {
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.speaker_2_fill,
                title: 'Speech Provider',
                subtitle:
                    speechProviderId ==
                        ModelSettingsService.elevenLabsSpeechProviderId
                    ? 'ElevenLabs'
                    : 'Groq',
                onTap: _showSpeechProviderSheet,
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: ModelSettingsService.instance.speechProviderId,
            builder: (context, speechProviderId, _) {
              if (speechProviderId ==
                  ModelSettingsService.elevenLabsSpeechProviderId) {
                return ValueListenableBuilder<String?>(
                  valueListenable:
                      ModelSettingsService.instance.elevenLabsVoiceName,
                  builder: (context, voiceName, _) => _buildNavTile(
                    theme,
                    icon: CupertinoIcons.waveform,
                    title: 'Response Voice',
                    subtitle: voiceName ?? 'Choose an ElevenLabs voice',
                    onTap: _showElevenLabsVoiceSheet,
                  ),
                );
              }
              return ValueListenableBuilder<String>(
                valueListenable: ModelSettingsService.instance.groqVoiceId,
                builder: (context, voiceId, _) {
                  final voice = ModelSettingsService.instance.currentGroqVoice;
                  return _buildNavTile(
                    theme,
                    icon: CupertinoIcons.speaker_2_fill,
                    title: 'Response Voice',
                    subtitle: '${voice.name} · ${voice.gender}',
                    onTap: _showGroqVoiceSheet,
                  );
                },
              );
            },
          ),
          ValueListenableBuilder<UserBubbleStyle>(
            valueListenable: BubbleStyleSettingsService.instance.style,
            builder: (context, style, _) {
              return _buildNavTile(
                theme,
                icon: CupertinoIcons.chat_bubble_2_fill,
                title: 'Message bubble',
                subtitle: '${style.label} style for your messages',
                onTap: _showBubbleStyleSheet,
              );
            },
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.checkmark_shield,
            title: 'Permissions',
            subtitle: 'Notifications and background mode',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PermissionsScreen()),
            ),
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.archivebox,
            title: 'Backup & Restore',
            subtitle: 'Backup & Restore finances data',
            onTap: _showBackupRestoreSheet,
          ),
          _buildNavTile(
            theme,
            icon: CupertinoIcons.sparkles,
            title: 'Onboarding',
            subtitle: 'Replay the welcome tour',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(isReplay: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    ThemeData theme, {
    IconData? icon,
    Widget? leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    assert(icon != null || leading != null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Center(
                  child:
                      leading ??
                      Icon(icon, size: 24, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyLeading(ThemeData theme, String currency) {
    return Tooltip(
      message: currency,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: AutoSizeText(
          currency,
          maxLines: 1,
          maxFontSize: 22,
          minFontSize: 14,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _openInsights() async {
    final entries = await FinanceService.instance.getAll();
    if (!mounted) return;
    final now = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceInsightsScreen(
          entries: List.from(entries),
          selectedMonth: DateTime(now.year, now.month),
        ),
      ),
    );
  }

  Future<void> _showCurrencyScreen() async {
    await CurrencyPickerScreen.show(context);
  }

  Future<void> _showModelSheet() async {
    final selected = await ModelPickerSheet.show(
      context,
      selectedModel: ModelSettingsService.instance.current,
    );
    if (selected == null) return;
    await ModelSettingsService.instance.setModel(selected);
  }

  Future<void> _showSpeechProviderSheet() async {
    final theme = Theme.of(context);
    final selected = await ResponsiveInfoSheet.show<String>(
      context,
      title: 'Choose Speech Provider',
      headerIcon: Icon(
        CupertinoIcons.cloud_fill,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _buildSpeechProviderOption(
          theme,
          id: ModelSettingsService.groqSpeechProviderId,
          name: 'Groq',
          description: 'Orpheus voices using your Groq API key',
        ),
        const SizedBox(height: 8),
        _buildSpeechProviderOption(
          theme,
          id: ModelSettingsService.elevenLabsSpeechProviderId,
          name: 'ElevenLabs',
          description: 'Flash v2.5 voices using your ElevenLabs credits',
        ),
      ],
    );
    if (selected == null) return;
    await ModelSettingsService.instance.setSpeechProvider(selected);
  }

  Widget _buildSpeechProviderOption(
    ThemeData theme, {
    required String id,
    required String name,
    required String description,
  }) {
    final selected = id == ModelSettingsService.instance.currentSpeechProvider;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.pop(context, id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  Future<void> _showGroqVoiceSheet() async {
    final theme = Theme.of(context);
    final selected = await ResponsiveInfoSheet.show<String>(
      context,
      title: 'Choose Response Voice',
      headerIcon: Icon(
        CupertinoIcons.speaker_2_fill,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _GroqVoicePicker(
          selectedVoiceId: ModelSettingsService.instance.groqVoiceId.value,
          onSelected: (voiceId) => Navigator.pop(context, voiceId),
        ),
      ],
    );
    if (selected == null) return;
    await ModelSettingsService.instance.setGroqVoice(selected);
  }

  Future<void> _showElevenLabsVoiceSheet() async {
    final theme = Theme.of(context);
    final selected = await ResponsiveInfoSheet.show<ElevenLabsVoice>(
      context,
      title: 'Choose ElevenLabs Voice',
      headerIcon: Icon(
        CupertinoIcons.waveform,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _ElevenLabsVoicePicker(
          selectedVoiceId:
              ModelSettingsService.instance.elevenLabsVoiceId.value,
          onSelected: (voice) => Navigator.pop(context, voice),
        ),
      ],
    );
    if (selected == null) return;
    await ModelSettingsService.instance.setElevenLabsVoice(
      id: selected.id,
      name: selected.name,
    );
  }

  Future<void> _showBubbleStyleSheet() async {
    final theme = Theme.of(context);
    await ResponsiveInfoSheet.show<void>(
      context,
      title: 'Select bubble style',
      headerIcon: Icon(
        CupertinoIcons.chat_bubble_2_fill,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: const [_BubbleStylePicker()],
    );
  }

  Future<void> _showBackupRestoreSheet() async {
    final theme = Theme.of(context);
    await ResponsiveInfoSheet.show<void>(
      context,
      title: 'Backup & Restore',
      headerIcon: Icon(
        CupertinoIcons.archivebox,
        size: 30,
        color: AppTheme.readableOn(theme.colorScheme.primary),
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_upload,
          title: 'Backup',
          subtitle: 'Create a dated JSON backup file',
          onTap: () {
            Navigator.pop(context);
            _exportBackup();
          },
        ),
        const SizedBox(height: 8),
        _buildSheetAction(
          theme,
          icon: CupertinoIcons.cloud_download,
          title: 'Restore',
          subtitle: 'Pick a JSON backup file to restore',
          onTap: () {
            Navigator.pop(context);
            _restoreBackup();
          },
        ),
      ],
    );
  }

  Widget _buildSheetAction(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      await AppBackupService.instance.shareBackup();
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Backup Failed: $e',
        type: ToastificationType.error,
      );
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;

      final file = File(result.path!);
      if (!await file.exists()) {
        if (!mounted) return;
        showAppToast(
          context,
          message: 'File Not Found',
          type: ToastificationType.error,
        );
        return;
      }

      final restoreResult = await AppBackupService.instance.restoreFromFile(
        file,
      );

      if (!mounted) return;
      if (restoreResult['ok'] == true) {
        showAppToast(
          context,
          message:
              restoreResult['message']?.toString() ??
              'Backup Restored Successfully!',
          type: ToastificationType.success,
        );
      } else {
        showAppToast(
          context,
          message: restoreResult['error']?.toString() ?? 'Restore Failed',
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Restore Failed: $e',
        type: ToastificationType.error,
      );
    }
  }
}

class _ElevenLabsVoicePicker extends StatefulWidget {
  const _ElevenLabsVoicePicker({
    required this.selectedVoiceId,
    required this.onSelected,
  });

  final String? selectedVoiceId;
  final ValueChanged<ElevenLabsVoice> onSelected;

  @override
  State<_ElevenLabsVoicePicker> createState() => _ElevenLabsVoicePickerState();
}

class _ElevenLabsVoicePickerState extends State<_ElevenLabsVoicePicker> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ElevenLabsAudioService _audioService = ElevenLabsAudioService();
  late Future<List<ElevenLabsVoice>> _voicesFuture;
  String? _previewingVoiceId;
  Completer<void>? _activePlaybackCompletion;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _voicesFuture = _audioService.listVoices();
  }

  @override
  void dispose() {
    _previewGeneration++;
    _completeActivePlayback();
    unawaited(_audioPlayer.stop());
    _audioPlayer.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(ElevenLabsVoice voice) async {
    if (_previewingVoiceId == voice.id) {
      await _cancelPreview();
      return;
    }

    final generation = ++_previewGeneration;
    await _audioPlayer.stop();
    _completeActivePlayback();
    if (!mounted || generation != _previewGeneration) return;
    setState(() => _previewingVoiceId = voice.id);

    File? generatedPreviewFile;
    try {
      final previewUrl = voice.previewUrl;
      if (previewUrl != null && previewUrl.isNotEmpty) {
        await _playSource(UrlSource(previewUrl), generation);
      } else {
        final audio = await _audioService.synthesize(
          'Hello, I am ${voice.name}, your Budget AI voice assistant.',
          voiceId: voice.id,
        );
        if (!mounted || generation != _previewGeneration) return;
        final temporaryDirectory = await getTemporaryDirectory();
        generatedPreviewFile = File(
          '${temporaryDirectory.path}/elevenlabs_voice_preview_'
          '${voice.id}_${DateTime.now().microsecondsSinceEpoch}.mp3',
        );
        await generatedPreviewFile.writeAsBytes(audio, flush: true);
        await _playSource(
          DeviceFileSource(generatedPreviewFile.path),
          generation,
        );
      }
    } catch (error) {
      if (!mounted || generation != _previewGeneration) return;
      showAppToast(
        context,
        message:
            'Could not preview ${voice.name}. '
            '${error.toString().replaceFirst('Exception: ', '')}',
        type: ToastificationType.error,
      );
    } finally {
      if (generatedPreviewFile != null) {
        try {
          if (await generatedPreviewFile.exists()) {
            await generatedPreviewFile.delete();
          }
        } catch (_) {}
      }
      if (mounted && generation == _previewGeneration) {
        setState(() => _previewingVoiceId = null);
      }
    }
  }

  Future<void> _playSource(Source source, int generation) async {
    final completed = Completer<void>();
    _activePlaybackCompletion = completed;
    Object? playbackError;
    final completionSubscription = _audioPlayer.onPlayerComplete.listen(
      (_) {
        if (!completed.isCompleted) completed.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        playbackError = error;
        if (!completed.isCompleted) completed.complete();
      },
    );
    try {
      if (generation != _previewGeneration) return;
      await _audioPlayer.play(source);
      await completed.future.timeout(const Duration(minutes: 1));
      if (playbackError != null) throw playbackError!;
    } finally {
      if (identical(_activePlaybackCompletion, completed)) {
        _activePlaybackCompletion = null;
      }
      await completionSubscription.cancel();
    }
  }

  Future<void> _cancelPreview() async {
    _previewGeneration++;
    _completeActivePlayback();
    await _audioPlayer.stop();
    if (mounted) setState(() => _previewingVoiceId = null);
  }

  void _completeActivePlayback() {
    final completion = _activePlaybackCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    _activePlaybackCompletion = null;
  }

  void _retry() {
    setState(() => _voicesFuture = _audioService.listVoices());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ElevenLabsVoice>>(
      future: _voicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load ElevenLabs voices. Check ELEVENLABS_API_KEY and try again.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(CupertinoIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          );
        }
        final voices = snapshot.data ?? const <ElevenLabsVoice>[];
        if (voices.isEmpty) {
          return Text(
            'No voices are available for this ElevenLabs account.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium,
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Previews use ElevenLabs\' supplied samples when available and do not consume synthesis credits.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < voices.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _buildVoiceOption(theme, voices[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildVoiceOption(ThemeData theme, ElevenLabsVoice voice) {
    final selected = voice.id == widget.selectedVoiceId;
    final isPreviewing = voice.id == _previewingVoiceId;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => widget.onSelected(voice),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    voice.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (voice.detail.isNotEmpty)
                    Text(
                      voice.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            _buildPreviewButton(theme, voice, isPreviewing),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewButton(
    ThemeData theme,
    ElevenLabsVoice voice,
    bool isPreviewing,
  ) {
    return IconButton(
      tooltip: isPreviewing
          ? 'Stop ${voice.name} preview'
          : 'Preview ${voice.name}',
      onPressed: () => _togglePreview(voice),
      icon: isPreviewing
          ? SizedBox.square(
              dimension: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                  Icon(
                    CupertinoIcons.stop_fill,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            )
          : Icon(
              CupertinoIcons.play_circle_fill,
              color: theme.colorScheme.primary,
              size: 28,
            ),
    );
  }
}

class _GroqVoicePicker extends StatefulWidget {
  const _GroqVoicePicker({
    required this.selectedVoiceId,
    required this.onSelected,
  });

  final String selectedVoiceId;
  final ValueChanged<String> onSelected;

  @override
  State<_GroqVoicePicker> createState() => _GroqVoicePickerState();
}

class _GroqVoicePickerState extends State<_GroqVoicePicker> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final GroqAudioService _audioService = GroqAudioService();
  String? _previewingVoiceId;
  Completer<void>? _activePlaybackCompletion;
  int _previewGeneration = 0;

  @override
  void dispose() {
    _previewGeneration++;
    _completeActivePlayback();
    unawaited(_audioPlayer.stop());
    _audioPlayer.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(GroqVoiceOption voice) async {
    if (_previewingVoiceId == voice.id) {
      await _cancelPreview();
      return;
    }

    final generation = ++_previewGeneration;
    await _audioPlayer.stop();
    _completeActivePlayback();
    if (!mounted || generation != _previewGeneration) return;
    setState(() => _previewingVoiceId = voice.id);

    try {
      final audio = await _audioService.synthesize(
        'Hello, I am ${voice.name}, your Budget AI voice assistant.',
        voice: voice.id,
      );
      if (!mounted || generation != _previewGeneration) return;
      await _playWavePreview(audio, voice.id, generation);
    } catch (error) {
      if (!mounted || generation != _previewGeneration) return;
      showAppToast(
        context,
        message:
            'Could not preview ${voice.name}. '
            '${error.toString().replaceFirst('Exception: ', '')}',
        type: ToastificationType.error,
      );
    } finally {
      if (mounted && generation == _previewGeneration) {
        setState(() => _previewingVoiceId = null);
      }
    }
  }

  Future<void> _cancelPreview() async {
    _previewGeneration++;
    _completeActivePlayback();
    await _audioPlayer.stop();
    if (mounted) setState(() => _previewingVoiceId = null);
  }

  void _completeActivePlayback() {
    final completion = _activePlaybackCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    _activePlaybackCompletion = null;
  }

  Future<void> _playWavePreview(
    List<int> audio,
    String voiceId,
    int generation,
  ) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final audioFile = File(
      '${temporaryDirectory.path}/groq_voice_preview_'
      '${voiceId}_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await audioFile.writeAsBytes(audio, flush: true);

    final completed = Completer<void>();
    _activePlaybackCompletion = completed;
    Object? playbackError;
    final completionSubscription = _audioPlayer.onPlayerComplete.listen(
      (_) {
        if (!completed.isCompleted) completed.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        playbackError = error;
        if (!completed.isCompleted) completed.complete();
      },
    );

    try {
      if (generation != _previewGeneration) return;
      await _audioPlayer.play(DeviceFileSource(audioFile.path));
      await completed.future.timeout(const Duration(minutes: 1));
      if (playbackError != null) throw playbackError!;
    } finally {
      if (identical(_activePlaybackCompletion, completed)) {
        _activePlaybackCompletion = null;
      }
      await completionSubscription.cancel();
      try {
        if (await audioFile.exists()) await audioFile.delete();
      } catch (_) {
        // Preview cleanup should not surface as a playback failure.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ModelSettingsService.groqVoices.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildVoiceOption(theme, ModelSettingsService.groqVoices[i]),
        ],
      ],
    );
  }

  Widget _buildVoiceOption(ThemeData theme, GroqVoiceOption voice) {
    final selected = voice.id == widget.selectedVoiceId;
    final isPreviewing = voice.id == _previewingVoiceId;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => widget.onSelected(voice.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    voice.name,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    voice.gender,
                    style: AppTheme.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isPreviewing
                  ? 'Stop ${voice.name} preview'
                  : 'Preview ${voice.name}',
              onPressed: () => _togglePreview(voice),
              icon: isPreviewing
                  ? SizedBox.square(
                      dimension: 28,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                          Icon(
                            CupertinoIcons.stop_fill,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    )
                  : Icon(
                      CupertinoIcons.play_circle_fill,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleStylePicker extends StatefulWidget {
  const _BubbleStylePicker();

  @override
  State<_BubbleStylePicker> createState() => _BubbleStylePickerState();
}

class _BubbleStylePickerState extends State<_BubbleStylePicker> {
  late UserBubbleStyle _selected;

  @override
  void initState() {
    super.initState();
    _selected = BubbleStyleSettingsService.instance.current;
  }

  Future<void> _select(UserBubbleStyle style) async {
    if (style == _selected) return;
    setState(() => _selected = style);
    HapticFeedback.selectionClick();
    await BubbleStyleSettingsService.instance.setStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewForeground = UserBubbleStyleSurface.foregroundColor(
      context,
      _selected,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: UserBubbleStyleSurface(
                key: ValueKey(_selected),
                style: _selected,
                child: Text(
                  'Your budget chats can match your style. Choose it Nicely',
                  style: AppTheme.bodyMedium.copyWith(
                    color: previewForeground,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Designed for Budget AI',
          style: AppTheme.headingSmall.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Tap a look to apply it. Existing and new chats update together.',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: UserBubbleStyle.values.length,
          itemBuilder: (context, index) {
            final style = UserBubbleStyle.values[index];
            return _BubbleStyleOption(
              style: style,
              selected: style == _selected,
              onTap: () => _select(style),
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _BubbleStyleOption extends StatelessWidget {
  const _BubbleStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final UserBubbleStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = UserBubbleStyleSurface.foregroundColor(context, style);

    return Semantics(
      selected: selected,
      button: true,
      label: '${style.label} message bubble',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: UserBubbleStyleSurface(
                      style: style,
                      preview: true,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 3,
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      style.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsNameEditor extends StatefulWidget {
  const _SettingsNameEditor();

  @override
  State<_SettingsNameEditor> createState() => _SettingsNameEditorState();
}

class _SettingsNameEditorState extends State<_SettingsNameEditor> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: UserNameSettingsService.instance.current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_isEditing || _isSaving) return;
    final currentName = UserNameSettingsService.instance.current;
    _controller.value = TextEditingValue(
      text: currentName,
      selection: TextSelection.collapsed(offset: currentName.length),
    );
    setState(() => _isEditing = true);
    _focusNode.requestFocus();
  }

  void _closeKeyboard() {
    if (!_isEditing || _isSaving) return;
    _focusNode.unfocus();
    setState(() => _isEditing = false);
  }

  void _toggleKeyboard() {
    if (_isEditing) {
      _closeKeyboard();
    } else {
      _startEditing();
    }
  }

  void _enterLetter(String letter) {
    if (_controller.text.length >= 28) return;
    final current = _controller.text;
    final shouldCapitalize =
        current.isEmpty || current.endsWith(' ') || current.endsWith('.');
    _appendText(shouldCapitalize ? letter : letter.toLowerCase());
  }

  void _enterPeriod() {
    final current = _controller.text;
    if (current.isEmpty ||
        current.endsWith(' ') ||
        current.endsWith('.') ||
        current.length >= 28) {
      return;
    }
    _appendText('.');
  }

  void _enterSpace() {
    final current = _controller.text;
    if (current.isEmpty || current.endsWith(' ') || current.length >= 28) {
      return;
    }
    _appendText(' ');
  }

  void _backspace() {
    final current = _controller.text;
    if (current.isEmpty) return;
    final updated = current.substring(0, current.length - 1);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  void _appendText(String addition) {
    final updated = '${_controller.text}$addition';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    setState(() {});
  }

  Future<void> _saveName() async {
    if (_isSaving) return;
    final name = _controller.text.trim();
    setState(() => _isSaving = true);
    await Future.wait([
      UserNameSettingsService.instance.setUserName(name),
      Future<void>.delayed(const Duration(milliseconds: 280)),
    ]);
    if (!mounted) return;
    _focusNode.unfocus();
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    HapticFeedback.lightImpact();
    showAppToast(
      context,
      message: name.isEmpty ? 'Name cleared' : 'Name updated to $name',
      type: ToastificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final savedName = UserNameSettingsService.instance.current;
    final firstName = savedName.split(RegExp(r'\s+')).firstOrNull ?? '';
    final showSavedSummary = savedName.isNotEmpty && !_isEditing;
    final iconContainerSize = screenSize.shortestSide * 0.123;
    final actionSize = screenSize.shortestSide * 0.097;
    final horizontalInset = screenSize.width * 0.031;
    final verticalInset = screenSize.height * 0.014;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleKeyboard,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalInset,
                vertical: verticalInset,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(screenSize.shortestSide),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                children: [
                  Container(
                    width: iconContainerSize,
                    height: iconContainerSize,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.person_fill,
                      size: screenSize.shortestSide * 0.051,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  SizedBox(width: horizontalInset),
                  Expanded(
                    child: SizedBox(
                      height: iconContainerSize,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: showSavedSummary
                              ? Align(
                                  key: const ValueKey(
                                    'settings-saved-name-summary',
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              savedName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTheme.headingSmall
                                                  .copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface,
                                                    fontSize:
                                                        screenSize
                                                            .shortestSide *
                                                        0.04,
                                                  ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: screenSize.width * 0.01,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Icon(
                                              CupertinoIcons.pencil,
                                              color: theme.colorScheme.primary,
                                              size:
                                                  screenSize.shortestSide *
                                                  0.04,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'I’ll call you $firstName',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.bodySmall.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize:
                                              screenSize.shortestSide * 0.032,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : TextField(
                                  key: const ValueKey(
                                    'settings-name-edit-field',
                                  ),
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  readOnly: true,
                                  showCursor: _isEditing,
                                  enableInteractiveSelection: false,
                                  onTap: _toggleKeyboard,
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
                                  cursorColor: theme.colorScheme.primary,
                                  cursorWidth: screenSize.shortestSide * 0.0075,
                                  cursorHeight: screenSize.shortestSide * 0.07,
                                  cursorRadius: const Radius.circular(32),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontFamily: 'Boldonse',
                                    fontSize: screenSize.shortestSide * 0.046,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'What should I call you?',
                                    hintStyle: TextStyle(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.3),
                                      fontFamily: 'Boldonse',
                                      fontSize: screenSize.shortestSide * 0.04,
                                    ),
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!showSavedSummary) ...[
                    SizedBox(width: screenSize.width * 0.021),
                    SizedBox(
                      width: actionSize,
                      height: actionSize,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _isSaving
                            ? Material(
                                key: const ValueKey('settings-name-saving'),
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                child: Center(
                                  child: SizedBox(
                                    width: actionSize * 0.42,
                                    height: actionSize * 0.42,
                                    child: CircularProgressIndicator(
                                      strokeWidth:
                                          screenSize.shortestSide * 0.005,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              )
                            : Material(
                                key: ValueKey(
                                  _isEditing
                                      ? 'settings-name-close'
                                      : 'settings-name-edit',
                                ),
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: _isEditing
                                      ? _closeKeyboard
                                      : _startEditing,
                                  customBorder: const CircleBorder(),
                                  child: Center(
                                    child: Icon(
                                      _isEditing
                                          ? CupertinoIcons.xmark
                                          : CupertinoIcons.pencil,
                                      color: theme.colorScheme.onPrimary,
                                      size: actionSize * 0.48,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _isEditing
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InlineNameKeyboard(
                      onLetter: _enterLetter,
                      onPeriod: _enterPeriod,
                      onSpace: _enterSpace,
                      onBackspace: _backspace,
                      onDone: _saveName,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

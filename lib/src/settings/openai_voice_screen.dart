import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:budget_ai/src/chat/openai_voice.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/model_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

class OpenAIVoiceScreen extends StatefulWidget {
  const OpenAIVoiceScreen({super.key});

  @override
  State<OpenAIVoiceScreen> createState() => _OpenAIVoiceScreenState();
}

class _OpenAIVoiceScreenState extends State<OpenAIVoiceScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingVoiceId;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceId = null);
    });
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _select(OpenAIVoice voice) async {
    HapticFeedback.selectionClick();
    await ModelSettingsService.instance.setVoice(voice.id);
    if (mounted) setState(() {});
  }

  Future<void> _preview(OpenAIVoice voice) async {
    try {
      if (_playingVoiceId == voice.id) {
        await _player.stop();
        if (mounted) setState(() => _playingVoiceId = null);
        return;
      }
      await _player.stop();
      await _player.play(AssetSource(voice.previewAsset));
      if (mounted) setState(() => _playingVoiceId = voice.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingVoiceId = null);
      showAppToast(
        context,
        message: 'This bundled preview could not be played.',
        type: ToastificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = ModelSettingsService.instance.currentVoice;
    return Scaffold(
      appBar: AppBar(title: const Text('Output voice')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
            child: Text(
              'Previews are bundled with the app. Playing them never calls OpenAI and has no API cost. Replies use AI-generated speech.',
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final voice in OpenAIVoices.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => _select(voice),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: selected == voice.id
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.4),
                      width: selected == voice.id ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected == voice.id
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle,
                        color: selected == voice.id
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  voice.name,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (voice.recommended) ...[
                                  const SizedBox(width: 7),
                                  Text(
                                    'Recommended',
                                    style: AppTheme.bodySmall.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              voice.description,
                              style: AppTheme.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: _playingVoiceId == voice.id
                            ? 'Stop preview'
                            : 'Play bundled preview',
                        onPressed: () => _preview(voice),
                        icon: Icon(
                          _playingVoiceId == voice.id
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.play_fill,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

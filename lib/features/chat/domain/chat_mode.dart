import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum ChatMode { defaultMode, fastChat }

class ChatModePreset {
  const ChatModePreset({
    required this.mode,
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.toolsEnabled,
    required this.systemPromptHint,
  });

  final ChatMode mode;
  final String id;
  final String name;
  final String description;
  final IconData icon;

  // null = default tool settings, false = no tools enabled.
  final bool? toolsEnabled;

  final String systemPromptHint;

  bool get isDefault => mode == ChatMode.defaultMode;
}

class ChatModes {
  ChatModes._();

  static const presets = <ChatModePreset>[
    ChatModePreset(
      mode: ChatMode.defaultMode,
      id: 'default',
      name: 'Default',
      description: 'All tools enabled. Your standard assistant experience.',
      icon: CupertinoIcons.square_grid_2x2,
      toolsEnabled: null,
      systemPromptHint: '',
    ),
    ChatModePreset(
      mode: ChatMode.fastChat,
      id: 'fast_chat',
      name: 'Fast',
      description: 'Pure conversation — no tools. Fastest responses.',
      icon: Icons.flash_on_rounded,
      toolsEnabled: false,
      systemPromptHint: '',
    ),
  ];

  static final defaultPreset = presets.first;

  // In-app current mode — resets to default on restart.
  static ChatModePreset _current = defaultPreset;

  static ChatModePreset forId(String id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }

  static ChatModePreset current() => _current;

  /// Apply [preset] in memory only — resets to default on next startup.
  static Future<void> applyMode(ChatModePreset preset) async {
    _current = preset;
  }

  // ── Natural-language detection ─────────────────────────────────────────────

  // Maps lowercase keywords to preset IDs.
  static const _aliases = <String, String>{
    'default': 'default',
    'normal': 'default',
    'standard': 'default',
    'reset': 'default',
    'fast': 'fast_chat',
    'quick': 'fast_chat',
  };

  static final _actionPattern = RegExp(
    r'\b(change|switch|set|use|activate|enable|go to|move to)\b',
  );

  /// Returns the target [ChatModePreset] if [message] looks like a mode-change
  /// request, or null otherwise.
  static ChatModePreset? detectModeChangeFromMessage(String message) {
    final lower = message.toLowerCase().trim();
    if (!lower.contains('mode')) return null;
    if (!_actionPattern.hasMatch(lower)) return null;

    // Longest-match wins to avoid 'personal' winning over 'personal assistant'.
    String? bestId;
    int bestLen = 0;
    for (final entry in _aliases.entries) {
      if (lower.contains(entry.key) && entry.key.length > bestLen) {
        bestLen = entry.key.length;
        bestId = entry.value;
      }
    }
    return bestId != null ? forId(bestId) : null;
  }
}

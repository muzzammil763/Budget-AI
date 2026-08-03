import 'dart:convert';

import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/foundation.dart';

enum UserBubbleStyle {
  classic('Classic'),
  outline('Outline'),
  ledger('Ledger'),
  savings('Savings'),
  cashFlow('Cash flow'),
  growth('Growth'),
  receipt('Receipt'),
  nightBudget('Night budget'),
  vault('Vault'),
  paperCurl('Paper curl'),
  sketchFrame('Sketch frame'),
  custom('Custom');

  const UserBubbleStyle(this.label);

  final String label;

  bool get usesHandwrittenFont =>
      this == UserBubbleStyle.paperCurl || this == UserBubbleStyle.sketchFrame;
}

enum CustomBubbleShape {
  rounded('Rounded'),
  conversational('Chat'),
  pill('Pill'),
  angular('Angular'),
  ticket('Ticket');

  const CustomBubbleShape(this.label);

  final String label;
}

enum CustomBubblePattern {
  none('None'),
  dots('Dots'),
  diagonal('Diagonal'),
  grid('Grid'),
  waves('Waves');

  const CustomBubblePattern(this.label);

  final String label;
}

@immutable
class CustomBubbleStyle {
  const CustomBubbleStyle({
    required this.id,
    required this.name,
    required this.backgroundColorValue,
    required this.textColorValue,
    required this.shape,
    required this.pattern,
    this.patternColorValue = 0xFFFFFFFF,
  });

  factory CustomBubbleStyle.fromJson(Map<String, dynamic> json) {
    return CustomBubbleStyle(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Custom bubble',
      backgroundColorValue: json['background_color'] as int? ?? 0xFF2364AA,
      textColorValue: json['text_color'] as int? ?? 0xFFFFFFFF,
      patternColorValue:
          json['pattern_color'] as int? ??
          json['text_color'] as int? ??
          0xFFFFFFFF,
      shape: CustomBubbleShape.values.firstWhere(
        (value) => value.name == json['shape'],
        orElse: () => CustomBubbleShape.rounded,
      ),
      pattern: CustomBubblePattern.values.firstWhere(
        (value) => value.name == json['pattern'],
        orElse: () => CustomBubblePattern.none,
      ),
    );
  }

  static const fallback = CustomBubbleStyle(
    id: 'fallback',
    name: 'Custom bubble',
    backgroundColorValue: 0xFF2364AA,
    textColorValue: 0xFFFFFFFF,
    patternColorValue: 0xFFFFFFFF,
    shape: CustomBubbleShape.rounded,
    pattern: CustomBubblePattern.none,
  );

  final String id;
  final String name;
  final int backgroundColorValue;
  final int textColorValue;
  final int patternColorValue;
  final CustomBubbleShape shape;
  final CustomBubblePattern pattern;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'background_color': backgroundColorValue,
    'text_color': textColorValue,
    'pattern_color': patternColorValue,
    'shape': shape.name,
    'pattern': pattern.name,
  };

  @override
  bool operator ==(Object other) =>
      other is CustomBubbleStyle &&
      other.id == id &&
      other.name == name &&
      other.backgroundColorValue == backgroundColorValue &&
      other.textColorValue == textColorValue &&
      other.patternColorValue == patternColorValue &&
      other.shape == shape &&
      other.pattern == pattern;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    backgroundColorValue,
    textColorValue,
    patternColorValue,
    shape,
    pattern,
  );
}

class BubbleStyleSettingsService {
  BubbleStyleSettingsService._();

  static final BubbleStyleSettingsService instance =
      BubbleStyleSettingsService._();
  static const String _styleKey = 'budget_user_bubble_style';

  final ValueNotifier<UserBubbleStyle> style = ValueNotifier<UserBubbleStyle>(
    UserBubbleStyle.classic,
  );
  final ValueNotifier<List<CustomBubbleStyle>> customStyles =
      ValueNotifier<List<CustomBubbleStyle>>(<CustomBubbleStyle>[]);
  final LocalSettingsStore _settings = LocalSettingsStore.instance;
  String? _activeCustomStyleId;

  Future<void> initialize() async {
    _applySerialized(await _settings.getString(_styleKey) ?? '');
  }

  Future<void> setStyle(UserBubbleStyle value) async {
    if (value == UserBubbleStyle.custom && currentCustomStyle == null) return;
    style.value = value;
    await _persist();
  }

  Future<void> setCustomStyle(String id) async {
    if (!customStyles.value.any((candidate) => candidate.id == id)) return;
    _activeCustomStyleId = id;
    if (style.value == UserBubbleStyle.custom) {
      style.value = UserBubbleStyle.classic;
      style.value = UserBubbleStyle.custom;
    } else {
      style.value = UserBubbleStyle.custom;
    }
    await _persist();
  }

  String? customStyleValidationError(String name, {String? originalId}) {
    final normalized = name.trim();
    if (normalized.isEmpty) return 'Enter a style name';
    if (normalized.length > 30) {
      return 'Use no more than 30 characters';
    }
    final lower = normalized.toLowerCase();
    if (UserBubbleStyle.values
        .where((style) => style != UserBubbleStyle.custom)
        .any((style) => style.label.toLowerCase() == lower)) {
      return 'That name is already used by a preset';
    }
    if (customStyles.value.any(
      (style) => style.id != originalId && style.name.toLowerCase() == lower,
    )) {
      return 'That custom style already exists';
    }
    return null;
  }

  Future<CustomBubbleStyle?> saveCustomStyle({
    String? originalId,
    required String name,
    required int backgroundColorValue,
    required int textColorValue,
    required int patternColorValue,
    required CustomBubbleShape shape,
    required CustomBubblePattern pattern,
  }) async {
    if (customStyleValidationError(name, originalId: originalId) != null) {
      return null;
    }
    final id =
        originalId ??
        'bubble_${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
    final saved = CustomBubbleStyle(
      id: id,
      name: name.trim(),
      backgroundColorValue: backgroundColorValue,
      textColorValue: textColorValue,
      patternColorValue: patternColorValue,
      shape: shape,
      pattern: pattern,
    );
    final updated = [...customStyles.value];
    final index = updated.indexWhere((style) => style.id == id);
    if (index == -1) {
      updated.add(saved);
    } else {
      updated[index] = saved;
    }
    customStyles.value = updated;
    _activeCustomStyleId = id;
    if (style.value == UserBubbleStyle.custom) {
      style.value = UserBubbleStyle.classic;
      style.value = UserBubbleStyle.custom;
    } else {
      style.value = UserBubbleStyle.custom;
    }
    await _persist();
    return saved;
  }

  Future<bool> deleteCustomStyle(String id) async {
    final updated = [...customStyles.value];
    final index = updated.indexWhere((style) => style.id == id);
    if (index == -1) return false;
    updated.removeAt(index);
    final wasSelected =
        style.value == UserBubbleStyle.custom && _activeCustomStyleId == id;
    customStyles.value = updated;
    if (_activeCustomStyleId == id) {
      _activeCustomStyleId = updated.isEmpty ? null : updated.first.id;
    }
    if (wasSelected) style.value = UserBubbleStyle.classic;
    await _persist();
    return true;
  }

  Future<void> applySyncedValue(String value) async {
    _applySerialized(value);
    await _settings.setValue(
      _styleKey,
      serializedValue,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
  }

  Future<void> applySyncedState(
    String selectedValue,
    List<Map<String, dynamic>> syncedCustomStyles,
  ) async {
    final decodedStyles = syncedCustomStyles
        .map(CustomBubbleStyle.fromJson)
        .where((style) => style.id.isNotEmpty)
        .toList(growable: false);
    customStyles.value = decodedStyles;
    if (selectedValue.startsWith('custom:')) {
      _activeCustomStyleId = selectedValue.substring('custom:'.length);
      style.value = currentCustomStyle == null
          ? UserBubbleStyle.classic
          : UserBubbleStyle.custom;
    } else {
      _activeCustomStyleId = decodedStyles.isEmpty
          ? null
          : decodedStyles.first.id;
      style.value = UserBubbleStyle.values.firstWhere(
        (candidate) =>
            candidate != UserBubbleStyle.custom &&
            candidate.name == selectedValue,
        orElse: () => UserBubbleStyle.classic,
      );
    }
    await _settings.setValue(
      _styleKey,
      serializedValue,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
  }

  Future<void> applySyncedStyle(UserBubbleStyle value) {
    return applySyncedValue(value.name);
  }

  void _applySerialized(String saved) {
    if (saved.startsWith('{')) {
      try {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        final decodedStyles = (json['custom_styles'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  CustomBubbleStyle.fromJson(Map<String, dynamic>.from(value)),
            )
            .where((style) => style.id.isNotEmpty)
            .toList(growable: false);
        customStyles.value = decodedStyles;
        _activeCustomStyleId = json['active_custom_id'] as String?;
        final selectedName = json['selected'] as String? ?? '';
        final selected = UserBubbleStyle.values.firstWhere(
          (candidate) => candidate.name == selectedName,
          orElse: () => UserBubbleStyle.classic,
        );
        style.value =
            selected == UserBubbleStyle.custom && currentCustomStyle == null
            ? UserBubbleStyle.classic
            : selected;
        return;
      } catch (_) {
        // Fall through to the legacy preset parser.
      }
    }

    customStyles.value = const [];
    _activeCustomStyleId = null;
    final migrated = switch (saved) {
      'flexingCat' => UserBubbleStyle.paperCurl,
      'facepalm' => UserBubbleStyle.sketchFrame,
      _ => null,
    };
    style.value = UserBubbleStyle.values.firstWhere(
      (candidate) =>
          candidate != UserBubbleStyle.custom && candidate.name == saved,
      orElse: () => migrated ?? UserBubbleStyle.classic,
    );
  }

  Future<void> _persist() {
    return _settings.setString(
      _styleKey,
      serializedValue,
      scope: SettingSyncScope.account,
    );
  }

  String get serializedValue {
    if (customStyles.value.isEmpty) return style.value.name;
    return jsonEncode({
      'version': 1,
      'selected': style.value.name,
      'active_custom_id': _activeCustomStyleId,
      'custom_styles': customStyles.value
          .map((style) => style.toJson())
          .toList(growable: false),
    });
  }

  String get syncedSelectionValue => current == UserBubbleStyle.custom
      ? 'custom:${currentCustomStyle?.id ?? ''}'
      : current.name;

  List<Map<String, Object>> get syncedCustomStyles =>
      customStyles.value.map((style) => style.toJson()).toList(growable: false);

  UserBubbleStyle get current => style.value;

  CustomBubbleStyle? get currentCustomStyle {
    for (final candidate in customStyles.value) {
      if (candidate.id == _activeCustomStyleId) return candidate;
    }
    return null;
  }

  String get currentLabel => current == UserBubbleStyle.custom
      ? currentCustomStyle?.name ?? UserBubbleStyle.custom.label
      : current.label;
}

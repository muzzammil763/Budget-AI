import 'package:budget_ai/src/storage/local_settings_store.dart';
import 'package:flutter/widgets.dart';

const int kMaxCustomCurrencyCharacters = 5;

const List<CurrencyOption> kPresetCurrencyOptions = [
  CurrencyOption(displayText: 'Rs', name: 'Pakistani Rupee symbol'),
  CurrencyOption(displayText: 'PKR', name: 'Pakistani Rupee code'),
  CurrencyOption(displayText: r'$', name: 'US Dollar symbol'),
  CurrencyOption(displayText: 'USD', name: 'US Dollar code'),
  CurrencyOption(displayText: '€', name: 'Euro symbol'),
  CurrencyOption(displayText: 'EUR', name: 'Euro code'),
  CurrencyOption(displayText: '£', name: 'British Pound symbol'),
  CurrencyOption(displayText: 'GBP', name: 'British Pound code'),
  CurrencyOption(displayText: 'INR', name: 'Indian Rupee code'),
  CurrencyOption(displayText: 'AED', name: 'UAE Dirham'),
  CurrencyOption(displayText: 'SAR', name: 'Saudi Riyal'),
  CurrencyOption(displayText: 'CAD', name: 'Canadian Dollar'),
  CurrencyOption(displayText: 'AUD', name: 'Australian Dollar'),
  CurrencyOption(displayText: 'JPY', name: 'Japanese Yen'),
];

class CurrencyOption {
  const CurrencyOption({required this.displayText, required this.name});

  final String displayText;
  final String name;

  bool get isSymbol => displayText.length == 1 && !_isAsciiLetter(displayText);

  static bool _isAsciiLetter(String value) {
    final code = value.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}

class CurrencySettingsService {
  CurrencySettingsService._();

  static final CurrencySettingsService instance = CurrencySettingsService._();
  static const String _currencyKey = 'budget_currency_display_text';
  static const String _customCurrenciesKey = 'budget_custom_currencies';

  final ValueNotifier<String> currency = ValueNotifier<String>('USD');
  final ValueNotifier<List<String>> customCurrencies =
      ValueNotifier<List<String>>(<String>[]);
  final LocalSettingsStore _settings = LocalSettingsStore.instance;

  Future<void> initialize() async {
    final savedCustomCurrencies =
        await _settings.getStringList(_customCurrenciesKey) ?? <String>[];
    customCurrencies.value = _normalizeCustomCurrencies(savedCustomCurrencies);
    final saved = (await _settings.getString(_currencyKey))?.trim();
    if (saved != null && saved.isNotEmpty) {
      currency.value = saved;
      await _saveCustomCurrencyIfNeeded(saved);
    }
  }

  void resetLocalState() {
    currency.value = 'USD';
    customCurrencies.value = <String>[];
  }

  Future<void> setCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    currency.value = normalized;
    await _saveCustomCurrencyIfNeeded(normalized);
    await _settings.setString(
      _currencyKey,
      normalized,
      scope: SettingSyncScope.account,
    );
  }

  String? customCurrencyValidationError(String value, {String? originalValue}) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'Enter a currency display';
    if (normalized.characters.length > kMaxCustomCurrencyCharacters) {
      return 'Use no more than $kMaxCustomCurrencyCharacters characters';
    }
    final normalizedLower = normalized.toLowerCase();
    if (kPresetCurrencyOptions.any(
      (option) => option.displayText.toLowerCase() == normalizedLower,
    )) {
      return 'That currency display is already in the preset list';
    }
    final originalLower = originalValue?.trim().toLowerCase();
    if (customCurrencies.value.any(
      (currency) =>
          currency.toLowerCase() == normalizedLower &&
          currency.toLowerCase() != originalLower,
    )) {
      return 'That custom currency already exists';
    }
    return null;
  }

  Future<bool> saveCustomCurrency(String value, {String? originalValue}) async {
    final normalized = value.trim();
    if (customCurrencyValidationError(
          normalized,
          originalValue: originalValue,
        ) !=
        null) {
      return false;
    }

    final updated = [...customCurrencies.value];
    final original = originalValue?.trim();
    if (original == null) {
      updated.add(normalized);
    } else {
      final index = updated.indexWhere(
        (currency) => currency.toLowerCase() == original.toLowerCase(),
      );
      if (index == -1) return false;
      updated[index] = normalized;
    }

    final shouldSelect =
        original == null ||
        currency.value.toLowerCase() == original.toLowerCase();
    customCurrencies.value = updated;
    if (shouldSelect) currency.value = normalized;

    await _settings.setStringList(
      _customCurrenciesKey,
      updated,
      scope: SettingSyncScope.account,
    );
    if (shouldSelect) {
      await _settings.setString(
        _currencyKey,
        normalized,
        scope: SettingSyncScope.account,
      );
    }
    return true;
  }

  Future<bool> deleteCustomCurrency(String value) async {
    final normalized = value.trim();
    final updated = [...customCurrencies.value];
    final index = updated.indexWhere(
      (currency) => currency.toLowerCase() == normalized.toLowerCase(),
    );
    if (index == -1) return false;

    final deleted = updated.removeAt(index);
    final wasSelected = currency.value.toLowerCase() == deleted.toLowerCase();
    customCurrencies.value = updated;
    if (wasSelected) currency.value = 'USD';

    await _settings.setStringList(
      _customCurrenciesKey,
      updated,
      scope: SettingSyncScope.account,
    );
    if (wasSelected) {
      await _settings.setString(
        _currencyKey,
        'USD',
        scope: SettingSyncScope.account,
      );
    }
    return true;
  }

  Future<void> applySyncedState(
    String value,
    List<String> syncedCustomCurrencies,
  ) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final custom = _normalizeCustomCurrencies(syncedCustomCurrencies);
    customCurrencies.value = custom;
    currency.value = normalized;
    await _settings.setValue(
      _customCurrenciesKey,
      custom,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
    await _settings.setValue(
      _currencyKey,
      normalized,
      scope: SettingSyncScope.account,
      pendingSync: false,
    );
  }

  String get current => currency.value;

  List<CurrencyOption> get availableOptions => [
    ...kPresetCurrencyOptions,
    ...customCurrencies.value.map(
      (currency) =>
          CurrencyOption(displayText: currency, name: 'Custom Display'),
    ),
  ];

  String get promptDescription {
    CurrencyOption? preset;
    for (final option in kPresetCurrencyOptions) {
      if (option.displayText == current) {
        preset = option;
        break;
      }
    }
    if (preset == null) return current;
    return '${preset.name} ($current)';
  }

  String formatAmount(
    double amount, {
    bool forceSign = false,
    String? currency,
  }) {
    final sign = amount < 0
        ? '-'
        : forceSign && amount > 0
        ? '+'
        : '';
    final formatted = _formatNumber(amount.abs());
    final token = currency ?? current;
    final prefixSymbols = {r'$', '€', '£', '₹', '¥'};
    if (prefixSymbols.contains(token)) {
      return '$sign$token$formatted';
    }
    return '$sign$formatted $token';
  }

  String _formatNumber(double amount) {
    final intPart = amount.toInt();
    final str = intPart.toString();
    if (str.length <= 3) return str;
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  Future<void> _saveCustomCurrencyIfNeeded(String value) async {
    final isPreset = kPresetCurrencyOptions.any(
      (option) => option.displayText.toLowerCase() == value.toLowerCase(),
    );
    final alreadySaved = customCurrencies.value.any(
      (currency) => currency.toLowerCase() == value.toLowerCase(),
    );
    if (isPreset ||
        alreadySaved ||
        value.characters.length > kMaxCustomCurrencyCharacters) {
      return;
    }

    final updated = [...customCurrencies.value, value];
    customCurrencies.value = updated;
    await _settings.setStringList(
      _customCurrenciesKey,
      updated,
      scope: SettingSyncScope.account,
    );
  }

  List<String> _normalizeCustomCurrencies(List<String> values) {
    final normalized = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty ||
          kPresetCurrencyOptions.any(
            (option) =>
                option.displayText.toLowerCase() == trimmed.toLowerCase(),
          ) ||
          normalized.any(
            (currency) => currency.toLowerCase() == trimmed.toLowerCase(),
          )) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }
}

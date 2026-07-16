import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<CurrencyOption> kPresetCurrencyOptions = [
  CurrencyOption(displayText: 'Rs', name: 'Pakistani Rupee symbol'),
  CurrencyOption(displayText: 'PKR', name: 'Pakistani Rupee code'),
  CurrencyOption(displayText: r'$', name: 'US Dollar symbol'),
  CurrencyOption(displayText: 'USD', name: 'US Dollar code'),
  CurrencyOption(displayText: '€', name: 'Euro symbol'),
  CurrencyOption(displayText: 'EUR', name: 'Euro code'),
  CurrencyOption(displayText: '£', name: 'British Pound symbol'),
  CurrencyOption(displayText: 'GBP', name: 'British Pound code'),
  CurrencyOption(displayText: '₹', name: 'Indian Rupee symbol'),
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
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    final savedCustomCurrencies =
        await _preferences.getStringList(_customCurrenciesKey) ?? <String>[];
    customCurrencies.value = _normalizeCustomCurrencies(savedCustomCurrencies);
    final saved = (await _preferences.getString(_currencyKey))?.trim();
    if (saved != null && saved.isNotEmpty) {
      currency.value = saved;
      await _saveCustomCurrencyIfNeeded(saved);
    }
  }

  Future<void> setCurrency(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await _saveCustomCurrencyIfNeeded(normalized);
    await _preferences.setString(_currencyKey, normalized);
    currency.value = normalized;
  }

  String get current => currency.value;

  List<CurrencyOption> get availableOptions => [
    ...kPresetCurrencyOptions,
    ...customCurrencies.value.map(
      (currency) =>
          CurrencyOption(displayText: currency, name: 'Custom display'),
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

  String formatAmount(double amount, {bool forceSign = false}) {
    final sign = amount < 0
        ? '-'
        : forceSign && amount > 0
        ? '+'
        : '';
    final formatted = _formatNumber(amount.abs());
    final token = current;
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
    if (isPreset || alreadySaved) return;

    final updated = [...customCurrencies.value, value];
    customCurrencies.value = updated;
    await _preferences.setStringList(_customCurrenciesKey, updated);
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

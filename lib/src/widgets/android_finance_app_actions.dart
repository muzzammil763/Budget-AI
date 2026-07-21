import 'dart:io';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles Google Assistant App Action deep links delivered by MainActivity.
class AndroidFinanceAppActions {
  AndroidFinanceAppActions._();

  static const MethodChannel _channel = MethodChannel(
    'budget_ai/android_app_action',
  );

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _initialized = false;
  static Future<void> _actionQueue = Future<void>.value();

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'financeAction' && call.arguments is String) {
        await _enqueue(call.arguments as String);
      }
    });
    final initialUri = await _channel.invokeMethod<String>('getInitialAction');
    if (initialUri != null) await _enqueue(initialUri);
  }

  static Future<void> _enqueue(String rawUri) {
    _actionQueue = _actionQueue.then((_) => _handle(rawUri));
    return _actionQueue;
  }

  static Future<void> _handle(String rawUri) async {
    try {
      final uri = Uri.parse(rawUri);
      if (uri.scheme != 'budgetai' || uri.host != 'finance') return;
      final amount = double.tryParse(uri.queryParameters['amount'] ?? '') ?? 0;
      final description = (uri.queryParameters['description'] ?? '').trim();
      final isIncome = uri.pathSegments.contains('add-income');
      if (amount <= 0 || description.isEmpty) {
        await _respond(
          'I could not understand the amount and description. Please try again.',
        );
        return;
      }

      final result = await addFinanceEntryFromToolArgs({
        'description': description,
        'amount': amount,
        'category': description,
      }, type: isIncome ? FinanceEntryType.income : FinanceEntryType.expense);
      if (result is Map && result['ok'] == true) {
        final formatted = CurrencySettingsService.instance.formatAmount(amount);
        await _respond(
          isIncome
              ? 'Added $formatted income from $description to Budget AI.'
              : 'Added $formatted for $description to Budget AI.',
        );
        revision.value++;
      } else {
        await _respond('Budget AI could not save that entry.');
      }
    } catch (error) {
      debugPrint('[AndroidAppAction] Could not handle action: $error');
      await _respond('Budget AI could not save that entry.');
    }
  }

  static Future<void> _respond(String message) async {
    await _channel.invokeMethod<void>('speakConfirmation', {
      'message': message,
    });
  }
}

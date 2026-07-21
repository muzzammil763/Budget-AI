import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// The App Group and keys shared by Flutter, the WidgetKit extension, and Siri.
class BudgetHomeWidgetSync {
  BudgetHomeWidgetSync._();

  static const appGroupId = 'group.com.muzamil.budget.ai';
  static const iOSWidgetKind = 'BudgetAIWidget';
  static const androidWidgetName = 'BudgetAIWidgetProvider';
  static const qualifiedAndroidWidgetName =
      'com.budgetai.android.BudgetAIWidgetProvider';

  static const entriesKey = 'budget_ai_widget_entries';
  static const pendingEntriesKey = 'budget_ai_pending_entries';
  static const monthExpenseKey = 'budget_ai_widget_month_expense';
  static const monthIncomeKey = 'budget_ai_widget_month_income';
  static const latestDescriptionKey = 'budget_ai_widget_latest_description';
  static const latestAmountKey = 'budget_ai_widget_latest_amount';
  static const latestTypeKey = 'budget_ai_widget_latest_type';
  static const currencyKey = 'budget_ai_widget_currency';
  static const lastUpdatedKey = 'budget_ai_widget_last_updated';

  static bool _groupConfigured = false;

  static Future<void> initialize() async {
    if ((!Platform.isIOS && !Platform.isAndroid) || _groupConfigured) return;
    try {
      if (Platform.isIOS) await HomeWidget.setAppGroupId(appGroupId);
      _groupConfigured = true;
    } catch (error) {
      debugPrint('[BudgetHomeWidget] Could not configure App Group: $error');
    }
  }

  static Future<String?> pendingEntriesJson() async {
    if (!Platform.isIOS) return null;
    await initialize();
    try {
      return HomeWidget.getWidgetData<String>(pendingEntriesKey);
    } catch (error) {
      debugPrint('[BudgetHomeWidget] Could not read Siri inbox: $error');
      return null;
    }
  }

  static Future<void> clearPendingEntries() async {
    if (!Platform.isIOS) return;
    await initialize();
    try {
      await HomeWidget.saveWidgetData<String>(pendingEntriesKey, '[]');
    } catch (error) {
      debugPrint('[BudgetHomeWidget] Could not clear Siri inbox: $error');
    }
  }

  static Future<void> syncEntries(
    Iterable<BudgetWidgetFinanceEntry> entries,
  ) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    await initialize();
    final list = entries.toList()..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final monthEntries = list.where(
      (entry) => entry.date.year == now.year && entry.date.month == now.month,
    );
    final expense = monthEntries
        .where((entry) => entry.type == 'expense')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final income = monthEntries
        .where((entry) => entry.type == 'income')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final latest = list.firstOrNull;

    try {
      await HomeWidget.saveWidgetData<String>(
        entriesKey,
        jsonEncode(list.map((entry) => entry.toJson()).toList()),
      );
      await HomeWidget.saveWidgetData<double>(monthExpenseKey, expense);
      await HomeWidget.saveWidgetData<double>(monthIncomeKey, income);
      await HomeWidget.saveWidgetData<String>(
        latestDescriptionKey,
        latest?.description ?? 'No entries yet',
      );
      await HomeWidget.saveWidgetData<double>(
        latestAmountKey,
        latest?.amount ?? 0,
      );
      await HomeWidget.saveWidgetData<String>(
        latestTypeKey,
        latest?.type ?? 'expense',
      );
      await HomeWidget.saveWidgetData<String>(
        currencyKey,
        CurrencySettingsService.instance.current,
      );
      await HomeWidget.saveWidgetData<String>(
        lastUpdatedKey,
        now.toIso8601String(),
      );
      await HomeWidget.updateWidget(
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidWidgetName,
        iOSName: iOSWidgetKind,
      );
    } catch (error) {
      // Finance persistence must remain successful if the widget is absent or
      // the App Group has not been provisioned on this build.
      debugPrint('[BudgetHomeWidget] Could not sync widget data: $error');
    }
  }
}

class BudgetWidgetFinanceEntry {
  const BudgetWidgetFinanceEntry({
    required this.id,
    required this.type,
    required this.date,
    required this.hasTime,
    required this.description,
    required this.amount,
    required this.category,
    required this.createdAt,
  });

  final String id;
  final String type;
  final DateTime date;
  final bool hasTime;
  final String description;
  final double amount;
  final String category;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'date': date.toIso8601String(),
    'has_time': hasTime,
    'description': description,
    'amount': amount,
    'category': category,
    'created_at': createdAt.toIso8601String(),
  };
}

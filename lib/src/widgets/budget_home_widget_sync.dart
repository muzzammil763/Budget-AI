import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// The App Group and keys shared by Flutter and the WidgetKit extension.
class BudgetHomeWidgetSync {
  BudgetHomeWidgetSync._();

  static const appGroupId = 'group.com.muzamil.budget.ai';
  static const iOSWidgetKinds = [
    'BudgetAIWidget',
    'BudgetAIExpenseTotalWidget',
    'BudgetAIIncomeTotalWidget',
    'BudgetAIMonthBalanceWidget',
    'BudgetAIRecentExpensesWidget',
    'BudgetAITodayExpensesWidget',
    'BudgetAIMonthComparisonWidget',
  ];
  static const androidWidgetName = 'BudgetAIWidgetProvider';
  static const qualifiedAndroidWidgetName =
      'com.budgetai.android.BudgetAIWidgetProvider';

  static const entriesKey = 'budget_ai_widget_entries';
  static const monthExpenseKey = 'budget_ai_widget_month_expense';
  static const monthIncomeKey = 'budget_ai_widget_month_income';
  static const latestDescriptionKey = 'budget_ai_widget_latest_description';
  static const latestAmountKey = 'budget_ai_widget_latest_amount';
  static const latestTypeKey = 'budget_ai_widget_latest_type';
  static const previousDescriptionKey = 'budget_ai_widget_previous_description';
  static const previousAmountKey = 'budget_ai_widget_previous_amount';
  static const previousTypeKey = 'budget_ai_widget_previous_type';
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

  static Future<void> syncEntries(
    Iterable<BudgetWidgetFinanceEntry> entries,
  ) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    await initialize();
    // Widgets compute monthly, daily, and recent views from every actual
    // expense and income entry; the wide widget's latest rows stay expenses.
    final all = entries.toList()..sort((a, b) => b.date.compareTo(a.date));
    final list = all.where((entry) => entry.type == 'expense').toList();
    final now = DateTime.now();
    final monthEntries = all.where(
      (entry) => entry.date.year == now.year && entry.date.month == now.month,
    );
    final expense = monthEntries
        .where((entry) => entry.type == 'expense')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final income = monthEntries
        .where((entry) => entry.type == 'income')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final latest = list.firstOrNull;
    final previous = list.length > 1 ? list[1] : null;

    try {
      await HomeWidget.saveWidgetData<String>(
        entriesKey,
        jsonEncode(all.map((entry) => entry.toJson()).toList()),
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
        previousDescriptionKey,
        previous?.description ?? '',
      );
      await HomeWidget.saveWidgetData<double>(
        previousAmountKey,
        previous?.amount ?? 0,
      );
      await HomeWidget.saveWidgetData<String>(
        previousTypeKey,
        previous?.type ?? 'expense',
      );
      await HomeWidget.saveWidgetData<String>(
        currencyKey,
        CurrencySettingsService.instance.current,
      );
      await HomeWidget.saveWidgetData<String>(
        lastUpdatedKey,
        now.toIso8601String(),
      );
      if (Platform.isIOS) {
        for (final kind in iOSWidgetKinds) {
          await HomeWidget.updateWidget(iOSName: kind);
        }
      } else {
        await HomeWidget.updateWidget(
          androidName: androidWidgetName,
          qualifiedAndroidName: qualifiedAndroidWidgetName,
        );
      }
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

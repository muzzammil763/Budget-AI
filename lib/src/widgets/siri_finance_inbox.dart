import 'dart:convert';
import 'dart:io';

import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/widgets/budget_home_widget_sync.dart';
import 'package:flutter/foundation.dart';

/// Imports entries written by the native Add Budget Entry App Shortcut.
class SiriFinanceInbox {
  SiriFinanceInbox._();

  static Future<void> _importQueue = Future<void>.value();

  static Future<void> importPendingEntries() {
    _importQueue = _importQueue.then((_) => _importPendingEntries());
    return _importQueue;
  }

  static Future<void> _importPendingEntries() async {
    if (!Platform.isIOS) return;
    final raw = await BudgetHomeWidgetSync.pendingEntriesJson();
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      final existingIds = (await FinanceService.instance.getAll())
          .map((entry) => entry.id)
          .toSet();

      for (final value in decoded) {
        if (value is! Map) continue;
        final entry = FinanceEntry.fromJson(Map<String, dynamic>.from(value));
        if (existingIds.add(entry.id)) {
          await FinanceService.instance.add(entry);
        }
      }
      await BudgetHomeWidgetSync.clearPendingEntries();
    } catch (error) {
      // Keep the inbox intact so a malformed or interrupted import can be
      // retried after an update instead of silently losing finance data.
      debugPrint('[SiriFinanceInbox] Could not import entries: $error');
    }
  }
}

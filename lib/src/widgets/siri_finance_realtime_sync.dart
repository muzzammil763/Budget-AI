import 'dart:io';

import 'package:budget_ai/src/widgets/siri_finance_inbox.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives cross-process App Intent changes while the Flutter app is alive.
class SiriFinanceRealtimeSync {
  SiriFinanceRealtimeSync._();

  static const MethodChannel _channel = MethodChannel('budget_ai/siri_finance');

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _initialized = false;

  static void initialize() {
    if (!Platform.isIOS || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'financeEntriesChanged') return;
      await SiriFinanceInbox.importPendingEntries();
      revision.value++;
    });
  }
}

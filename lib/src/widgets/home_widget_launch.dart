import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

enum HomeWidgetScreen { finances, insights }

/// Where a Home or Lock Screen widget tap should land.
@immutable
class HomeWidgetDestination {
  const HomeWidgetDestination({required this.screen, this.month, this.entryId});

  final HomeWidgetScreen screen;
  final DateTime? month;
  final String? entryId;

  /// Parses `budgetai://widget/<finances|insights>?month=yyyy-MM&entry=<id>`.
  /// Any other widget URL, such as Android's plain `budgetai://widget`,
  /// opens Finances on the current month.
  static HomeWidgetDestination? parse(Uri? uri) {
    if (uri == null || uri.scheme != 'budgetai' || uri.host != 'widget') {
      return null;
    }
    final path = uri.pathSegments.firstOrNull;
    final rawMonth = uri.queryParameters['month'];
    DateTime? month;
    if (rawMonth != null) {
      final parts = rawMonth.split('-');
      final year = parts.length == 2 ? int.tryParse(parts[0]) : null;
      final monthNumber = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (year != null && monthNumber != null) {
        month = DateTime(year, monthNumber);
      }
    }
    final entryId = uri.queryParameters['entry'];
    return HomeWidgetDestination(
      screen: path == 'insights'
          ? HomeWidgetScreen.insights
          : HomeWidgetScreen.finances,
      month: month,
      entryId: entryId == null || entryId.isEmpty ? null : entryId,
    );
  }
}

/// Collects widget taps from cold launches and while the app is running.
/// The signed-in chat screen consumes [pending] and navigates, so a tap
/// never bypasses sign-in.
class HomeWidgetLaunch {
  HomeWidgetLaunch._();

  static final ValueNotifier<HomeWidgetDestination?> pending = ValueNotifier(
    null,
  );
  static StreamSubscription<Uri?>? _subscription;

  static Future<void> initialize() async {
    if ((!Platform.isIOS && !Platform.isAndroid) || _subscription != null) {
      return;
    }
    _subscription = HomeWidget.widgetClicked.listen(_handle);
    try {
      _handle(await HomeWidget.initiallyLaunchedFromHomeWidget());
    } catch (error) {
      debugPrint('[HomeWidgetLaunch] Could not read launch URL: $error');
    }
  }

  static void _handle(Uri? uri) {
    final destination = HomeWidgetDestination.parse(uri);
    if (destination != null) pending.value = destination;
  }

  /// Returns and clears the pending destination.
  static HomeWidgetDestination? take() {
    final destination = pending.value;
    pending.value = null;
    return destination;
  }
}

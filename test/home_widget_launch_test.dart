import 'package:budget_ai/src/widgets/home_widget_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widget month taps open Finances on that month', () {
    final destination = HomeWidgetDestination.parse(
      Uri.parse('budgetai://widget/finances?homeWidget&month=2026-09'),
    );

    expect(destination?.screen, HomeWidgetScreen.finances);
    expect(destination?.month, DateTime(2026, 9));
    expect(destination?.entryId, isNull);
  });

  test('widget row taps carry the entry to open', () {
    final destination = HomeWidgetDestination.parse(
      Uri.parse(
        'budgetai://widget/finances?homeWidget&month=2026-10&entry=fin_42',
      ),
    );

    expect(destination?.entryId, 'fin_42');
    expect(destination?.month, DateTime(2026, 10));
  });

  test('insights taps and plain Android taps resolve', () {
    expect(
      HomeWidgetDestination.parse(
        Uri.parse('budgetai://widget/insights?homeWidget'),
      )?.screen,
      HomeWidgetScreen.insights,
    );
    final android = HomeWidgetDestination.parse(
      Uri.parse('budgetai://widget?homeWidget'),
    );
    expect(android?.screen, HomeWidgetScreen.finances);
    expect(android?.month, isNull);
  });

  test('non-widget links are ignored', () {
    expect(
      HomeWidgetDestination.parse(Uri.parse('budgetai://auth/confirm')),
      isNull,
    );
    expect(HomeWidgetDestination.parse(null), isNull);
  });
}

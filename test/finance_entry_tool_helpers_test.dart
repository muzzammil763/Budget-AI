import 'package:budget_ai/src/tools/finance_entry_tool_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new finance labels use title case and ampersands', () {
    expect(normalizeNewFinanceLabel('bottle and snacks'), 'Bottle & Snacks');
    expect(normalizeNewFinanceLabel('  monthly   salary  '), 'Monthly Salary');
  });

  test('new categories remain dynamic and never use Others', () {
    expect(
      normalizeNewFinanceCategory(
        'side hustle',
        description: 'Weekend Project',
      ),
      'Side Hustle',
    );
    expect(
      normalizeNewFinanceCategory('Others', description: 'Bottle & Snacks'),
      'Bottle & Snacks',
    );
  });
}

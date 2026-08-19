import 'package:budget_ai/src/helpers/notification_text_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speech text omits visual table cells and adds a cue', () {
    const markdown = '| Title | Amount |\n| --- | --- |\n| Fuel | Rs 250 |';
    expect(
      speechPlainText(markdown),
      'You can see the details in the table below.',
    );
  });

  group('notificationPlainText', () {
    test('removes Markdown formatting while preserving content', () {
      const markdown = '''
# **Monthly summary**

You spent *less* than [last month](https://example.com).

- **Income:** \$3,000
- `Expenses`: \$1,800
''';

      expect(notificationPlainText(markdown), '''Monthly summary

You spent less than last month.

• Income: \$3,000
• Expenses: \$1,800''');
    });

    test('preserves complete paragraphs, numbering, and fenced code', () {
      const markdown = '''
1) Review the category
2. Update the budget

```text
Rent: \$900
Utilities: \$120
```
''';

      expect(notificationPlainText(markdown), '''1. Review the category
2. Update the budget

Rent: \$900
Utilities: \$120''');
    });

    test('turns Markdown tables into readable lines', () {
      const markdown = '''
| Category | Amount |
| --- | ---: |
| **Food** | \$240 |
| Travel | \$80 |
''';

      expect(notificationPlainText(markdown), '''Category • Amount
Food • \$240
Travel • \$80''');
    });

    test('does not shorten a long response', () {
      final response = List.generate(
        100,
        (index) => '**Item ${index + 1}:** complete response content',
      ).join('\n');

      final plainText = notificationPlainText(response);

      expect(plainText, contains('Item 100: complete response content'));
      expect(plainText, isNot(contains('**')));
      expect(plainText, isNot(endsWith('...')));
    });

    test('preserves underscores inside identifiers', () {
      expect(
        notificationPlainText('Use user_name_settings or _another option_.'),
        'Use user_name_settings or another option.',
      );
    });
  });
}

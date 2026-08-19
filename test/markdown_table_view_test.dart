import 'package:budget_ai/src/chat/markdown_table_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  testWidgets('all table columns render from their leading edge', (
    tester,
  ) async {
    final rows = [
      CustomTableRow(
        isHeader: true,
        fields: [
          CustomTableField(data: 'Amount'),
          CustomTableField(data: 'Very Long Entry Name That Must Truncate'),
        ],
      ),
      CustomTableRow(
        fields: [
          CustomTableField(data: '15,290 Rs'),
          CustomTableField(
            data: 'A very long description that should truncate cleanly',
            alignment: TextAlign.right,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownTableView(
            tableRows: rows,
            textStyle: const TextStyle(fontSize: 16),
            config: const GptMarkdownConfig(),
          ),
        ),
      ),
    );

    for (final label in [
      'Amount',
      'Very Long Entry Name That Must Truncate',
      '15,290 Rs',
      'A very long description that should truncate cleanly',
    ]) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.textAlign, TextAlign.start);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
      final align = tester.widget<Align>(
        find.ancestor(of: find.text(label), matching: find.byType(Align)).first,
      );
      expect(align.alignment, AlignmentDirectional.centerStart);
    }

    final table = tester.widget<Table>(find.byType(Table));
    final amountWidth = table.columnWidths![0] as FixedColumnWidth;
    expect(amountWidth.value, greaterThan(68));
  });
}

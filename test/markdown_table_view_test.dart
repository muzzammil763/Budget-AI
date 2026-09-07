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
          CustomTableField(data: 'Period'),
          CustomTableField(data: 'Total', alignment: TextAlign.right),
        ],
      ),
      CustomTableRow(
        fields: [
          CustomTableField(data: 'August'),
          CustomTableField(data: '15,290 Rs', alignment: TextAlign.right),
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

    for (final label in ['Period', 'Total', 'August', '15,290 Rs']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.textAlign, TextAlign.start);
      final align = tester.widget<Align>(
        find.ancestor(of: find.text(label), matching: find.byType(Align)).first,
      );
      expect(align.alignment, AlignmentDirectional.centerStart);
    }
  });
}

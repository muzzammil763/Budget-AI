import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class MarkdownTableView extends StatelessWidget {
  final List<CustomTableRow> tableRows;
  final TextStyle textStyle;
  final GptMarkdownConfig config;

  const MarkdownTableView({
    super.key,
    required this.tableRows,
    required this.textStyle,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    if (tableRows.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstRowIsHeader = tableRows.first.isHeader;
    final hasHeader =
        firstRowIsHeader &&
        tableRows.first.fields.any((field) => field.data.trim().isNotEmpty);
    final bodyRows = firstRowIsHeader ? tableRows.skip(1).toList() : tableRows;
    final columnCount = tableRows.first.fields.length;
    final theme = Theme.of(context);
    final columnWidths = _buildColumnWidths(tableRows, columnCount);

    final table = Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(
              color: theme.colorScheme.primary,
              width: 1,
            ),
            verticalInside: BorderSide(
              color: theme.colorScheme.primary,
              width: 1,
            ),
          ),
          columnWidths: columnWidths,
          children: [
            if (hasHeader)
              TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.primary),
                children: tableRows.first.fields
                    .map((field) => _buildCell(context, field.data, true))
                    .toList(),
              ),
            ...bodyRows.map(
              (row) => TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.surface),
                children: row.fields
                    .map((field) => _buildCell(context, field.data, false))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scrollView = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: table,
          );

          if (!constraints.hasBoundedWidth) {
            return scrollView;
          }

          return SizedBox(width: constraints.maxWidth, child: scrollView);
        },
      ),
    );
  }

  Widget _buildCell(BuildContext context, String data, bool isHeader) {
    final theme = Theme.of(context);
    final cellTextStyle = textStyle.copyWith(
      color: isHeader
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurface,
      fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
      fontSize: isHeader ? 15 : (textStyle.fontSize ?? 14),
      height: 1.4,
    );
    final trimmedData = data.trim();
    const contentAlignment = TextAlign.center;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: DefaultTextStyle(
        style: cellTextStyle,
        child: _containsMarkdownSyntax(trimmedData)
            ? GptMarkdown(
                trimmedData,
                style: cellTextStyle,
                textAlign: contentAlignment,
                tableBuilder: null,
                onLinkTap: config.onLinkTap,
                highlightBuilder: config.highlightBuilder,
                linkBuilder: config.linkBuilder,
                imageBuilder: config.imageBuilder,
                orderedListBuilder: config.orderedListBuilder,
                unOrderedListBuilder: config.unOrderedListBuilder,
              )
            : Text(trimmedData, textAlign: contentAlignment),
      ),
    );
  }

  Map<int, TableColumnWidth> _buildColumnWidths(
    List<CustomTableRow> rows,
    int columnCount,
  ) {
    return {
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++)
        columnIndex: FixedColumnWidth(_estimateColumnWidth(rows, columnIndex)),
    };
  }

  double _estimateColumnWidth(List<CustomTableRow> rows, int columnIndex) {
    const horizontalCellPadding = 28.0;
    const minColumnWidth = 52.0;
    const maxColumnWidth = 320.0;
    var widestCell = 0.0;

    for (final row in rows) {
      if (columnIndex >= row.fields.length) continue;
      final text = row.fields[columnIndex].data.trim();
      final fontSize = row.isHeader ? 15.0 : (textStyle.fontSize ?? 14.0);
      final fontWeight = row.isHeader ? FontWeight.w700 : FontWeight.w500;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle.copyWith(fontSize: fontSize, fontWeight: fontWeight),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > widestCell) {
        widestCell = painter.width;
      }
    }

    return (widestCell + horizontalCellPadding)
        .clamp(minColumnWidth, maxColumnWidth)
        .toDouble();
  }

  bool _containsMarkdownSyntax(String text) {
    return RegExp(r'[`*_~\[\]<>#]|https?://').hasMatch(text);
  }
}

Widget buildStyledMarkdownTable(
  BuildContext context,
  List<CustomTableRow> tableRows,
  TextStyle textStyle,
  GptMarkdownConfig config,
) {
  return MarkdownTableView(
    tableRows: tableRows,
    textStyle: textStyle,
    config: config,
  );
}

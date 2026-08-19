import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class MarkdownTableGestureNotification extends Notification {
  const MarkdownTableGestureNotification({required this.isActive});

  final bool isActive;
}

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
    final baseColumnWidths = _estimateColumnWidths(tableRows, columnCount);
    final dividerColor = theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.12 : 0.09,
    );

    Widget buildTable(Map<int, TableColumnWidth> columnWidths) {
      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: dividerColor, width: 1.5),
          verticalInside: BorderSide(color: dividerColor, width: 1.5),
        ),
        columnWidths: columnWidths,
        children: [
          if (hasHeader)
            TableRow(
              children: tableRows.first.fields
                  .map((field) => _buildCell(context, field, true))
                  .toList(),
            ),
          for (var index = 0; index < bodyRows.length; index++)
            TableRow(
              children: bodyRows[index].fields
                  .map(
                    (field) => _buildCell(
                      context,
                      field,
                      index == bodyRows.length - 1 &&
                          _isSummaryRow(bodyRows[index]),
                    ),
                  )
                  .toList(),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolvedWidths = _resolveColumnWidths(
            baseColumnWidths,
            constraints.hasBoundedWidth ? constraints.maxWidth - 24 : null,
          );
          final columnWidths = {
            for (final entry in resolvedWidths.entries)
              entry.key: FixedColumnWidth(entry.value),
          };
          final table = constraints.hasBoundedWidth
              ? ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: (constraints.maxWidth - 24)
                        .clamp(0, double.infinity)
                        .toDouble(),
                  ),
                  child: buildTable(columnWidths),
                )
              : buildTable(columnWidths);
          final scrollView = _MarkdownTableHorizontalScroller(child: table);

          if (!constraints.hasBoundedWidth) {
            return scrollView;
          }

          return SizedBox(width: constraints.maxWidth, child: scrollView);
        },
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    CustomTableField field,
    bool isHeader,
  ) {
    final theme = Theme.of(context);
    final cellTextStyle = textStyle.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: isHeader ? FontWeight.bold : FontWeight.w400,
      fontSize: isHeader ? 16 : (textStyle.fontSize ?? 16),
    );
    final trimmedData = field.data.trim();
    // Chat tables use one consistent reading edge. Model-generated separator
    // alignment markers must not push numeric or comparison columns to the
    // far side of wide cells.
    const textAlign = TextAlign.start;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DefaultTextStyle(
          style: cellTextStyle,
          child: !isHeader && _containsMarkdownSyntax(trimmedData)
              ? GptMarkdown(
                  trimmedData,
                  style: cellTextStyle,
                  textAlign: textAlign,
                  tableBuilder: null,
                  onLinkTap: config.onLinkTap,
                  highlightBuilder: config.highlightBuilder,
                  linkBuilder: config.linkBuilder,
                  imageBuilder: config.imageBuilder,
                  orderedListBuilder: config.orderedListBuilder,
                  unOrderedListBuilder: config.unOrderedListBuilder,
                )
              : Text(
                  trimmedData,
                  textAlign: textAlign,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ),
    );
  }

  Map<int, double> _estimateColumnWidths(
    List<CustomTableRow> rows,
    int columnCount,
  ) {
    return {
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++)
        columnIndex: _estimateColumnWidth(rows, columnIndex),
    };
  }

  Map<int, double> _resolveColumnWidths(
    Map<int, double> baseWidths,
    double? availableWidth,
  ) {
    if (availableWidth == null) return baseWidths;
    final totalBase = baseWidths.values.fold<double>(0, (sum, w) => sum + w);
    if (totalBase <= 0 || totalBase >= availableWidth) return baseWidths;

    final extra = availableWidth - totalBase;
    return {
      for (final entry in baseWidths.entries)
        entry.key: entry.value + extra * (entry.value / totalBase),
    };
  }

  double _estimateColumnWidth(List<CustomTableRow> rows, int columnIndex) {
    const horizontalCellPadding = 24.0;
    const minColumnWidth = 68.0;
    const maxColumnWidth = 300.0;
    var widestCell = 0.0;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (columnIndex >= row.fields.length) continue;
      final text = row.fields[columnIndex].data.trim();
      final usesHeaderStyle =
          row.isHeader || (rowIndex == rows.length - 1 && _isSummaryRow(row));
      final fontSize = usesHeaderStyle ? 16.0 : (textStyle.fontSize ?? 16.0);
      final fontWeight = usesHeaderStyle ? FontWeight.bold : FontWeight.w400;
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

  bool _isSummaryRow(CustomTableRow row) {
    final text = row.fields
        .map((field) => field.data)
        .join(' ')
        .replaceAll(RegExp(r'[`*_~#]'), ' ')
        .toLowerCase();
    return RegExp(
      r'\b(total|subtotal|remaining|balance|net|saved|overspent|summary|result)\b',
    ).hasMatch(text);
  }
}

class _MarkdownTableHorizontalScroller extends StatefulWidget {
  const _MarkdownTableHorizontalScroller({required this.child});

  final Widget child;

  @override
  State<_MarkdownTableHorizontalScroller> createState() =>
      _MarkdownTableHorizontalScrollerState();
}

class _MarkdownTableHorizontalScrollerState
    extends State<_MarkdownTableHorizontalScroller> {
  final ScrollController _controller = ScrollController();
  int? _trackedPointer;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_trackedPointer != null) return;
    _trackedPointer = event.pointer;
    const MarkdownTableGestureNotification(isActive: true).dispatch(context);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_trackedPointer != event.pointer) return;
    _resetPointerTracking();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_trackedPointer == event.pointer) _resetPointerTracking();
  }

  void _resetPointerTracking() {
    _trackedPointer = null;
    if (mounted) {
      const MarkdownTableGestureNotification(isActive: false).dispatch(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: widget.child,
      ),
    );
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

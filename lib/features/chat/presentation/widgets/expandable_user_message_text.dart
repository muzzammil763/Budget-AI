import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';

class ExpandableUserMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const ExpandableUserMessageText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<ExpandableUserMessageText> createState() =>
      _ExpandableUserMessageTextState();
}

class _ExpandableUserMessageTextState extends State<ExpandableUserMessageText> {
  static const int _collapsedMaxLines = 12;

  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(text: widget.text, style: widget.style);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: Directionality.of(context),
          maxLines: _collapsedMaxLines,
        )..layout(maxWidth: constraints.maxWidth);

        final hasOverflow = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Text(
                widget.text,
                style: widget.style,
                maxLines: hasOverflow ? _collapsedMaxLines : null,
                overflow: hasOverflow
                    ? TextOverflow.fade
                    : TextOverflow.visible,
              ),
              secondChild: Text(widget.text, style: widget.style),
            ),
            if (hasOverflow) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      _isExpanded ? 'Show less' : 'Show more',
                      style: AppTheme.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

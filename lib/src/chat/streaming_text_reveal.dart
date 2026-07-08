import 'package:flutter/material.dart';

class StreamingTextReveal extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool isStreaming;
  final TextAlign textAlign;
  final Color cursorColor;

  const StreamingTextReveal({
    super.key,
    required this.text,
    this.style,
    required this.isStreaming,
    this.textAlign = TextAlign.start,
    required this.cursorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: textAlign, style: style);
  }
}

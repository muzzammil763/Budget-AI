import 'package:budget_ai/src/chat/chat_response_markdown.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI response markdown inherits the app font family', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatResponseMarkdown(
            text: 'A response from Budget AI.',
            isStreaming: false,
            onLinkTap: (_, _) async {},
          ),
        ),
      ),
    );

    final markdownTheme = tester.widget<Theme>(
      find.descendant(
        of: find.byType(ChatResponseMarkdown),
        matching: find.byType(Theme),
      ),
    );

    expect(
      markdownTheme.data.textTheme.bodyMedium?.fontFamily,
      AppTheme.defaultFontFamily,
    );
    expect(
      markdownTheme.data.textTheme.headlineLarge?.fontFamily,
      AppTheme.defaultFontFamily,
    );
  });
}

import 'package:budget_ai/src/chat/chat_activity_sections.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tool calls are visible and expand to arguments and results', (
    tester,
  ) async {
    final toolCall = ToolCall(
      id: 'summary-1',
      name: 'finance_summary',
      arguments: const {'month': 'August'},
      result: '{"total": 15290}',
      isComplete: true,
      status: ToolCallStatus.completed,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatToolCallSection(
            toolCall: toolCall,
            themeColor: Colors.blue,
            isInProgress: false,
          ),
        ),
      ),
    );

    expect(find.text('Finance Summary'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    await tester.tap(find.text('Finance Summary'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
    expect(find.textContaining('August'), findsWidgets);
    expect(find.textContaining('15290'), findsWidgets);
  });
}

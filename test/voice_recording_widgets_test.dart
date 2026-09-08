import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:budget_ai/src/chat/chat_response_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'pending text keeps the response inset and never recenters as its label grows',
    (tester) async {
      Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 320, child: child),
          ),
        ),
      );
      await tester.pumpWidget(
        host(ChatPendingResponse(startedAt: DateTime.now())),
      );
      final thinkingPosition = tester.getTopLeft(find.text('Thinking ...'));
      expect(thinkingPosition.dx, 12);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.getTopLeft(find.text('Budget AI is working ...')),
        thinkingPosition,
      );
      await tester.pumpWidget(
        host(
          ChatResponseMarkdown(
            text: 'Reply begins here.',
            isStreaming: false,
            onLinkTap: (_, _) async {},
          ),
        ),
      );
      final responseText = find
          .descendant(
            of: find.byType(ChatResponseMarkdown),
            matching: find.byType(RichText),
          )
          .first;
      expect(tester.getTopLeft(responseText), thinkingPosition);
    },
  );

  testWidgets(
    'moving pending content to the assistant slot keeps elapsed waiting time',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPendingResponse(
              startedAt: DateTime.now().subtract(const Duration(seconds: 3)),
            ),
          ),
        ),
      );
      expect(find.text('Budget AI is working ...'), findsOneWidget);
      expect(find.text('Thinking ...'), findsNothing);
    },
  );

  testWidgets('working status stays static and matches composer typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ChatWorkingWord(fontSize: 16))),
    );

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ChatWorkingWord),
        matching: find.byType(Text),
      ),
    );
    expect(texts, hasLength(1));
    expect(texts.single.data, 'Budget AI Working ...');
    for (final text in texts) {
      expect(text.style?.fontSize, 16);
      expect(text.style?.fontWeight, FontWeight.w400);
      expect(text.style?.fontFamily, 'Google Sans');
    }

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Budget AI Working ...'), findsOneWidget);
  });

  testWidgets('voice recording UI animates at compact composer widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 256,
              height: 56,
              child: Row(
                children: [
                  ChatVoiceRecordingPulse(),
                  SizedBox(width: 2),
                  Expanded(child: ChatVoiceRecordingStatus()),
                  SizedBox(width: 2),
                  SizedBox.square(
                    dimension: 44,
                    child: ColoredBox(
                      color: Colors.black,
                      child: ChatVoiceRecordingButtonIcon(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Listening'), findsOneWidget);
    expect(find.text('Release to transcribe & send'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(tester.takeException(), isNull);
  });
}

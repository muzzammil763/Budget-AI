import 'package:budget_ai/src/chat/chat_loading_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('working words match normal composer hint typography', (
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
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(text.style?.fontSize, 16);
      expect(text.style?.fontWeight, FontWeight.w400);
      expect(text.style?.fontFamily, 'Google Sans');
    }
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

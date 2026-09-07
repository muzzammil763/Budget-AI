import 'dart:convert';
import 'package:budget_ai/src/chat/chat_image_widgets.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
void main() {
  test('images survive serialization and copying of local messages', () {
    final user = ChatMessage(
      text: '',
      isUser: true,
      timestamp: DateTime(2026),
      images: [pixel],
    );
    final restored = ChatMessage.fromJson(
      jsonDecode(jsonEncode(user.toJson())),
    );
    expect(restored.copyWith(text: 'Receipt').images, [pixel]);
    final output = ChatMessageBlock(
      id: 'image',
      type: ChatMessageBlockType.image,
      text: pixel,
      isComplete: true,
    );
    expect(
      ChatMessageBlock.fromJson(output.toJson()).type,
      ChatMessageBlockType.image,
    );
    expect(ChatMessage.fromJson({'text': 'Old chat'}).images, isEmpty);
  });
  testWidgets('attachment preview opens viewer and exposes removal', (
    tester,
  ) async {
    int? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatImageStrip(
            images: [pixel],
            onRemove: (index) => removed = index,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Remove image 1'));
    expect(removed, 0);
    await tester.tap(find.byType(ChatImageView));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
  testWidgets('invalid saved image renders a fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChatImageView(dataUrl: 'invalid')),
    );
    expect(find.text('Image unavailable'), findsOneWidget);
  });
}

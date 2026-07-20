import 'package:budget_ai/src/chat/chat_empty_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat starters match the app finance capabilities', () {
    expect(chatStarterPrompts, hasLength(10));
    expect(
      chatStarterPrompts.map((starter) => starter.label).toSet(),
      hasLength(chatStarterPrompts.length),
    );

    final combined = chatStarterPrompts
        .map((starter) => '${starter.label} ${starter.prompt}'.toLowerCase())
        .join('\n');
    expect(combined, isNot(contains('what bills are coming up soon')));
    expect(combined, isNot(contains('safely spend today')));
    expect(combined, isNot(contains('debt payoff plan')));

    final bills = chatStarterPrompts.singleWhere(
      (starter) => starter.label == 'Estimate bills that may repeat',
    );
    expect(bills.prompt, contains('last 60 days'));
    expect(bills.prompt, contains('not a due-date or scheduled-bill list'));
  });
}

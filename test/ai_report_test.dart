import 'package:budget_ai/src/chat/ai_report.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('report sheet needs a reason before sending', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AiReplyActions(replyText: 'You spent \$107.', onCopy: () {}),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Report reply'));
    await tester.pumpAndSettle();
    expect(find.text('Report this reply'), findsOneWidget);
    for (final reason in AiReportReason.values) {
      expect(find.text(reason.label), findsOneWidget);
    }

    final send = find.byKey(const ValueKey('ai-report-send'));
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    // Still open: no reason was chosen.
    expect(find.text('Report this reply'), findsOneWidget);

    await tester.tap(find.text(AiReportReason.inaccurate.label));
    await tester.pumpAndSettle();
    expect(find.text('Report this reply'), findsOneWidget);
    // Let the "choose a reason" toast finish its timers.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });
}

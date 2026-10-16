import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/widgets/home_widget_catalog.dart';
import 'package:budget_ai/src/widgets/home_widget_gallery_screen.dart';
import 'package:budget_ai/src/widgets/home_widget_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 16, 18);

  FinanceEntry entry(
    String id,
    DateTime date,
    double amount, {
    String category = 'Food',
    FinanceEntryType type = FinanceEntryType.expense,
  }) => FinanceEntry(
    id: id,
    type: type,
    date: date,
    hasTime: false,
    description: id,
    amount: amount,
    category: category,
    createdAt: date,
  );

  test('preview numbers match what the native widgets compute', () {
    final snapshot = WidgetPreviewSnapshot(
      currency: '\$',
      now: now,
      entries: [
        entry('today_lunch', DateTime(2026, 10, 16, 12), 12.5),
        entry('rent', DateTime(2026, 10, 1), 1200, category: 'Bills'),
        entry(
          'salary',
          DateTime(2026, 10, 1),
          3000,
          type: FinanceEntryType.income,
        ),
        entry('last_month', DateTime(2026, 9, 20), 800, category: 'Bills'),
      ],
    );

    final october = snapshot.summary(0);
    expect(october.expense, 1212.5);
    expect(october.income, 3000);
    expect(october.expenseCount, 2);
    expect(snapshot.summary(-1).expense, 800);
    expect(snapshot.todayExpenses.map((e) => e.id), ['today_lunch']);
    expect(snapshot.recentExpenses(5).map((e) => e.id), [
      'today_lunch',
      'rent',
      'last_month',
    ]);
    expect(snapshot.categories(0).first.key, 'Bills');
    expect(snapshot.amount(1212.5), '\$1,212.50');
    expect(snapshot.amount(3000), '\$3,000');
    expect(
      WidgetPreviewSnapshot(
        entries: const [],
        currency: 'Rs',
        now: now,
      ).amount(42, sign: '−'),
      '−42 Rs',
    );
  });

  for (final brightness in Brightness.values) {
    for (final width in const [320.0, 430.0]) {
      testWidgets(
        'every widget preview lays out (${brightness.name}, ${width.toInt()})',
        (tester) async {
          final snapshots = [
            WidgetPreviewSnapshot.sample(currency: 'PKR', now: now),
            WidgetPreviewSnapshot(entries: const [], currency: '\$', now: now),
          ];
          for (final snapshot in snapshots) {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          for (final widget in homeWidgetCatalog)
                            HomeWidgetPreview(
                              definition: widget,
                              snapshot: snapshot,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('gallery lists the Android widgets with a manual guide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(FinanceService.instance.getAll);
    await tester.pumpWidget(const MaterialApp(home: HomeWidgetGalleryScreen()));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('Home Screen Widgets'), findsOneWidget);
    expect(find.byKey(const ValueKey('widget-gallery-guide')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('widget-gallery-sample-note')),
      findsOneWidget,
    );
    for (final widget in homeWidgetCatalog.where((w) => w.isOnAndroid)) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('widget-gallery-${widget.id}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(find.byKey(const ValueKey('widget-gallery-lock')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

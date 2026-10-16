import 'package:budget_ai/src/finances/finance_service.dart';
import 'package:budget_ai/src/settings/finance_data_safety.dart';
import 'package:budget_ai/src/settings/settings_screen.dart';
import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:budget_ai/src/sync/finance_sync_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FinanceSyncPreferenceService.instance.resetLocalState();
  });

  testWidgets('Budget Hub shows Cloud Sync off with backup and restore', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-restore')),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Cloud Sync'), findsOneWidget);
    expect(find.text('Entries are saved only on this device'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-backup')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-restore')), findsOneWidget);
  });

  testWidgets('signing out with local-only entries warns before erasing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      LocalFinanceStore.instance.resetVolatileFallback();
      await LocalFinanceStore.instance.replaceActive([
        {
          'id': 'local-only',
          'type': 'expense',
          'date': DateTime(2026, 10, 1).toIso8601String(),
          'description': 'Groceries',
          'amount': 40,
          'category': 'Food',
          'created_at': DateTime(2026, 10, 1).toIso8601String(),
        },
      ]);
      FinanceService.instance.invalidateCacheFromSync();
      await FinanceService.instance.getAll();
    });
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => FinanceDataSafety.confirmSignOut(
              context,
              signOut: () async => signedOut = true,
            ),
            child: const Text('Sign out'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Keep Your Entries Safe'), findsOneWidget);
    expect(find.textContaining('saved only on this device'), findsOneWidget);
    expect(find.text('Back Up Entries'), findsOneWidget);
    expect(find.text('Turn On Cloud Sync & Sign Out'), findsOneWidget);
    expect(find.text('Sign Out & Erase 1 entry'), findsOneWidget);

    await tester.tap(find.text('Sign Out & Erase 1 entry'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
    expect(find.text('Keep Your Entries Safe'), findsNothing);
  });
}

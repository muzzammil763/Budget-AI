import 'package:budget_ai/src/storage/local_finance_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = LocalFinanceStore.instance;

  setUp(store.resetVolatileFallback);

  test('unchanged finance rows stay clean and keep their revision', () async {
    final entry = <String, dynamic>{
      'id': 'entry-1',
      'description': 'Coffee',
      'amount': 5.0,
    };

    await store.replaceActive([entry]);
    final firstPending = await store.pendingRows();
    expect(firstPending, hasLength(1));
    expect(firstPending.single['revision'], 1);

    await store.markClean({'entry-1': 1});
    await store.replaceActive([entry]);

    expect(await store.pendingRows(), isEmpty);
  });

  test('a stale upload acknowledgement cannot clean a newer edit', () async {
    await store.replaceActive([
      <String, dynamic>{
        'id': 'entry-1',
        'description': 'Coffee',
        'amount': 5.0,
      },
    ]);
    await store.replaceActive([
      <String, dynamic>{
        'id': 'entry-1',
        'description': 'Coffee',
        'amount': 6.0,
      },
    ]);

    await store.markClean({'entry-1': 1});

    final pending = await store.pendingRows();
    expect(pending, hasLength(1));
    expect(pending.single['revision'], 2);
  });

  test('clean restored rows missing remotely are queued for upload', () async {
    await store.replaceActive([
      <String, dynamic>{
        'id': 'restored-entry',
        'description': 'Legacy expense',
        'amount': 20.0,
      },
    ]);
    await store.markClean({'restored-entry': 1});

    await store.markActiveMissingRemotePending(const {});

    final pending = await store.pendingRows();
    expect(pending, hasLength(1));
    expect(pending.single['id'], 'restored-entry');
    expect(pending.single['revision'], 2);
  });

  test('rows already present remotely are not re-queued', () async {
    await store.replaceActive([
      <String, dynamic>{
        'id': 'synced-entry',
        'description': 'Synced expense',
        'amount': 30.0,
      },
    ]);
    await store.markClean({'synced-entry': 1});

    await store.markActiveMissingRemotePending(const {'synced-entry'});

    expect(await store.pendingRows(), isEmpty);
  });
}

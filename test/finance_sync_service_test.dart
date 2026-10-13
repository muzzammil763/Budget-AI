import 'package:budget_ai/src/sync/finance_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finance rows round-trip through plain sync columns', () {
    final payload = {
      'id': 'fin_1',
      'type': 'income',
      'date': DateTime(2026, 10, 12, 14, 30).toIso8601String(),
      'has_time': true,
      'description': 'Salary',
      'amount': 1250.5,
      'category': 'Salary',
      'created_at': DateTime(2026, 10, 12, 14, 31).toIso8601String(),
    };
    final row = FinanceSyncService.remoteRow(
      userId: 'user',
      payload: payload,
      revision: 3,
      isDeleted: false,
      clientUpdatedAt: DateTime.utc(2026, 10, 12),
    );

    expect(row['id'], 'fin_1');
    expect(row['type'], 'income');
    expect(row['amount'], 1250.5);
    expect(row['revision'], 3);
    // PostgREST returns `timestamp` columns without fractional zeros.
    final returned = {
      ...row,
      'date': '2026-10-12T14:30:00',
      'created_at': '2026-10-12T14:31:00',
    };
    expect(FinanceSyncService.payloadFromRemote(returned), payload);
  });
}

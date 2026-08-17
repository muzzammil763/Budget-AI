import 'package:budget_ai/src/settings/admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy empty and unknown roles are treated as members', () {
    expect(parseAppUserRole(null), AppUserRole.member);
    expect(parseAppUserRole(''), AppUserRole.member);
    expect(parseAppUserRole('legacy'), AppUserRole.member);
  });

  test('admin usage percentages use each user override', () {
    final user = AdminUserInfo.fromJson({
      'user_id': 'user-id',
      'email': 'user@example.com',
      'role': 'admin',
      'request_count': 75,
      'monthly_request_limit': 100,
      'tokens_used': 250,
      'monthly_token_limit': 1000,
    });

    expect(user.role, AppUserRole.admin);
    expect(user.requestsFraction, 0.75);
    expect(user.tokensFraction, 0.25);
    expect(user.fastRequestsLimit, 100);
  });
}

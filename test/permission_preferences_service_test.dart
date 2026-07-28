import 'package:budget_ai/src/settings/permission_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding grants turn on the matching local preferences', () async {
    final service = PermissionPreferencesService.instance;
    final originalNotifications = service.notificationsEnabled.value;
    final originalBackground = service.backgroundEnabled.value;
    addTearDown(() {
      service.notificationsEnabled.value = originalNotifications;
      service.backgroundEnabled.value = originalBackground;
    });
    service.notificationsEnabled.value = false;
    service.backgroundEnabled.value = false;

    await service.recordOnboardingGrants(
      notificationsGranted: true,
      backgroundGranted: true,
    );

    expect(service.notificationsEnabled.value, isTrue);
    expect(service.backgroundEnabled.value, isTrue);
  });

  test('missing grants do not override existing local choices', () async {
    final service = PermissionPreferencesService.instance;
    final originalNotifications = service.notificationsEnabled.value;
    final originalBackground = service.backgroundEnabled.value;
    addTearDown(() {
      service.notificationsEnabled.value = originalNotifications;
      service.backgroundEnabled.value = originalBackground;
    });
    service.notificationsEnabled.value = true;
    service.backgroundEnabled.value = true;

    await service.recordOnboardingGrants(
      notificationsGranted: false,
      backgroundGranted: false,
    );

    expect(service.notificationsEnabled.value, isTrue);
    expect(service.backgroundEnabled.value, isTrue);
  });
}

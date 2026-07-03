import 'package:flutter/cupertino.dart';
import 'package:local_auth/local_auth.dart';
import 'package:budget_ai/core/widgets/responsive_info_sheet.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:toastification/toastification.dart';

Future<bool> confirmAuthenticatedDeletion({
  required BuildContext context,
  required String title,
  required String message,
  required String localizedReason,
  String unavailableMessage = 'Biometrics not available on this device',
  String failedMessage = 'Authentication failed. Item was not deleted.',
}) async {
  final confirmed = await ResponsiveInfoSheet.confirm(
    context,
    title: title,
    message: message,
    icon: CupertinoIcons.trash,
    confirmLabel: 'Continue',
  );

  if (confirmed != true || !context.mounted) return false;

  final localAuth = LocalAuthentication();
  try {
    final canCheckBiometrics = await localAuth.canCheckBiometrics;
    final isDeviceSupported = await localAuth.isDeviceSupported();

    if (!canCheckBiometrics && !isDeviceSupported) {
      if (context.mounted) {
        showAppToast(
          context,
          message: unavailableMessage,
          type: ToastificationType.error,
        );
      }
      return false;
    }

    final authenticated = await localAuth.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );

    if (!authenticated && context.mounted) {
      showAppToast(
        context,
        message: failedMessage,
        type: ToastificationType.error,
      );
    }
    return authenticated;
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: 'Authentication error: ${e.toString()}',
        type: ToastificationType.error,
      );
    }
    debugPrint('Authentication error: ${e.toString()}');
    return false;
  }
}

import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

void showAppToast(
  BuildContext context, {
  required String message,
  ToastificationType type = ToastificationType.success,
}) {
  final theme = Theme.of(context);
  switch (type) {
    case ToastificationType.success:
      break;
    case ToastificationType.error:
      break;
    case ToastificationType.warning:
      break;
    case ToastificationType.info:
      break;
  }

  Toastification().show(
    context: context,
    title: Text(
      maxLines: 8,
      message,
      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
    ),
    type: type,
    style: ToastificationStyle.flat,
    dragToClose: true,
    autoCloseDuration: const Duration(seconds: 2),
    borderSide: const BorderSide(color: Colors.transparent),
    showProgressBar: false,
    backgroundColor: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(8),
    boxShadow: [
      BoxShadow(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        spreadRadius: 0,
        blurRadius: 30,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        spreadRadius: 0,
        blurRadius: 30,
        offset: const Offset(2, 0),
      ),
    ],
  );
}

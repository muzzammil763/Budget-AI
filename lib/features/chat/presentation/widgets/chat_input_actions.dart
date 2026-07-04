import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ChatInputActions extends StatelessWidget {
  final bool isStreaming;
  final bool canSubmit;
  final bool isReady;
  final VoidCallback onCancelRequest;
  final VoidCallback onSendMessage;

  const ChatInputActions({
    super.key,
    required this.isStreaming,
    required this.canSubmit,
    required this.isReady,
    required this.onCancelRequest,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Spacer(),
        if (isStreaming && !canSubmit)
          IconButton(
            icon: const Icon(Icons.stop_rounded),
            onPressed: onCancelRequest,
            color: theme.colorScheme.onError,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: const CircleBorder(),
            ),
            iconSize: 24,
          )
        else
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: canSubmit ? 1.0 : 0.5,
            child: _SendActionButton(
              canSubmit: canSubmit,
              isReady: isReady,
              onTap: onSendMessage,
            ),
          ),
      ],
    );
  }
}

class _SendActionButton extends StatelessWidget {
  const _SendActionButton({
    required this.canSubmit,
    required this.isReady,
    required this.onTap,
  });

  final bool canSubmit;
  final bool isReady;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tapEnabled = canSubmit && isReady;
    final activeColor = theme.colorScheme.primary;
    final disabledColor = theme.colorScheme.primary.withValues(alpha: 0.12);
    final iconColor = tapEnabled
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary.withValues(alpha: 0.54);

    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: tapEnabled ? activeColor : disabledColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tapEnabled ? onTap : null,
          child: Center(
            child: Icon(CupertinoIcons.arrow_right, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }
}

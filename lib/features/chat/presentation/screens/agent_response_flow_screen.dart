import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/tools/settings/tool_name_formatter.dart';
import 'package:budget_ai/features/chat/data/services/chat_provider.dart';

class AgentResponseFlowScreen extends StatelessWidget {
  const AgentResponseFlowScreen({
    super.key,
    required this.userMessage,
    required this.assistantMessage,
    required this.systemPrompt,
    required this.systemPromptIsSnapshot,
  });

  static const double _kWidth = 720;

  final String userMessage;
  final ChatMessage assistantMessage;
  final String systemPrompt;
  final bool systemPromptIsSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = _blocksForMessage(assistantMessage);
    final thinkingBlocks = blocks
        .where((block) => block.type == ChatMessageBlockType.thinking)
        .where((block) => (block.text ?? '').trim().isNotEmpty)
        .toList();
    final toolCalls = blocks
        .where((block) => block.type == ChatMessageBlockType.toolCall)
        .map((block) => block.toolCall)
        .whereType<ToolCall>()
        .toList();
    final responseText = assistantMessage.text.trim();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text('Response Flow'),
      ),
      body: InteractiveViewer(
        constrained: false,
        minScale: 0.25,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: SizedBox(
            width: _kWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _FlowNode(
                  icon: CupertinoIcons.person_circle,
                  label: 'You sent a message',
                  sublabel: _oneLine(userMessage),
                  color: Colors.blueAccent,
                  details: userMessage,
                ),
                const _FlowArrow(),
                _FlowNode(
                  icon: CupertinoIcons.text_alignleft,
                  label: systemPromptIsSnapshot
                      ? 'System prompt snapshot sent'
                      : 'Current system prompt reconstruction',
                  sublabel:
                      'System rules, skills, memories, tools, and project context',
                  color: Colors.teal,
                  details: systemPrompt,
                ),
                const _FlowArrow(),
                _FlowNode(
                  icon: CupertinoIcons.bolt,
                  label: thinkingBlocks.isEmpty
                      ? 'AI thought about the task'
                      : 'AI thinking captured',
                  sublabel: thinkingBlocks.isEmpty
                      ? 'This model did not expose thinking text'
                      : '${thinkingBlocks.length} thinking block${thinkingBlocks.length == 1 ? '' : 's'}',
                  color: Colors.orange,
                  details: thinkingBlocks.isEmpty
                      ? 'No thinking text was exposed by this model for this response.'
                      : thinkingBlocks
                            .map((block) => block.text!.trim())
                            .join('\n\n---\n\n'),
                ),
                const _FlowArrow(),
                _FlowDecision(
                  label: toolCalls.isEmpty
                      ? 'No tool call needed'
                      : '${toolCalls.length} tool call${toolCalls.length == 1 ? '' : 's'} needed',
                ),
                const _FlowArrow(),
                if (toolCalls.isNotEmpty) ...[
                  for (var i = 0; i < toolCalls.length; i++) ...[
                    _ToolFlowNode(index: i + 1, toolCall: toolCalls[i]),
                    const _FlowArrow(),
                    _FlowNode(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      label: 'Tool result returned to AI',
                      sublabel: _toolStatusLabel(toolCalls[i]),
                      color: _toolStatusColor(toolCalls[i]),
                      details: _formatToolResult(toolCalls[i]),
                    ),
                    const _FlowArrow(),
                    _FlowNode(
                      icon: CupertinoIcons.repeat,
                      label: i == toolCalls.length - 1
                          ? 'AI checked whether the task was done'
                          : 'Loop continued',
                      sublabel: i == toolCalls.length - 1
                          ? 'No more tool calls were needed before the reply'
                          : 'The AI used the result and selected another tool',
                      color: Colors.orange,
                    ),
                    if (i != toolCalls.length - 1) const _FlowArrow(),
                  ],
                  const _FlowArrow(),
                ],
                _FlowNode(
                  icon: CupertinoIcons.chat_bubble_text,
                  label: 'Final reply written',
                  sublabel: responseText.isEmpty
                      ? 'No visible response text'
                      : _oneLine(responseText),
                  color: Colors.green,
                  details: responseText.isEmpty
                      ? 'No visible response text was saved for this response.'
                      : responseText,
                ),
                const _FlowArrow(),
                _FlowNode(
                  icon: CupertinoIcons.eye,
                  label: 'You saw the response',
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16),
                _HintCard(
                  text: systemPromptIsSnapshot
                      ? 'Tap any node to expand the data saved for this response.'
                      : 'Older responses may not have an exact prompt snapshot. This view uses the current reconstructed prompt for that node.',
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Pinch to zoom  ·  drag to pan',
                    style: AppTheme.bodySmall.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<ChatMessageBlock> _blocksForMessage(ChatMessage message) {
    if (message.blocks != null && message.blocks!.isNotEmpty) {
      return message.blocks!;
    }

    final blocks = <ChatMessageBlock>[];
    if ((message.thinkingText ?? '').trim().isNotEmpty) {
      blocks.add(
        ChatMessageBlock(
          id: 'thinking_${message.timestamp.microsecondsSinceEpoch}',
          type: ChatMessageBlockType.thinking,
          text: message.thinkingText,
          isComplete: message.isThinkingComplete,
        ),
      );
    }
    for (final toolCall in message.toolCalls ?? const <ToolCall>[]) {
      blocks.add(
        ChatMessageBlock(
          id: 'tool_${toolCall.id ?? blocks.length}',
          type: ChatMessageBlockType.toolCall,
          toolCall: toolCall,
          isComplete: toolCall.isComplete,
        ),
      );
    }
    if (message.text.trim().isNotEmpty) {
      blocks.add(
        ChatMessageBlock(
          id: 'response_${message.timestamp.microsecondsSinceEpoch}',
          type: ChatMessageBlockType.response,
          text: message.text,
          isComplete: true,
        ),
      );
    }
    return blocks;
  }

  static String _oneLine(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 96) return normalized;
    return '${normalized.substring(0, 96)}...';
  }

  static String _toolStatusLabel(ToolCall toolCall) {
    return switch (toolCall.status) {
      ToolCallStatus.completed => 'Completed',
      ToolCallStatus.failed => 'Failed',
      ToolCallStatus.awaitingApproval => 'Awaiting approval',
      ToolCallStatus.cancelled => 'Cancelled',
      ToolCallStatus.calling => 'Running',
      ToolCallStatus.creating => 'Creating',
      ToolCallStatus.pending => 'Pending',
    };
  }

  static Color _toolStatusColor(ToolCall toolCall) {
    return switch (toolCall.status) {
      ToolCallStatus.completed => Colors.green,
      ToolCallStatus.failed => Colors.red,
      ToolCallStatus.awaitingApproval => Colors.amber,
      ToolCallStatus.cancelled => Colors.grey,
      _ => Colors.purple,
    };
  }

  static String _formatToolResult(ToolCall toolCall) {
    final result = toolCall.result?.trim();
    if (result == null || result.isEmpty) {
      return 'No tool result was saved.';
    }
    return _prettyJsonOrText(result);
  }

  static String _prettyJsonOrText(String value) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonDecode(value));
    } catch (_) {
      return value;
    }
  }
}

class _ToolFlowNode extends StatelessWidget {
  const _ToolFlowNode({required this.index, required this.toolCall});

  final int index;
  final ToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    return _FlowNode(
      icon: CupertinoIcons.hammer,
      label: 'Tool $index: ${formatToolNameForUi(toolCall.name)}',
      sublabel: toolCall.name,
      color: Colors.purple,
      details: _formatToolCall(toolCall),
    );
  }

  static String _formatToolCall(ToolCall toolCall) {
    const encoder = JsonEncoder.withIndent('  ');
    final buffer = StringBuffer()
      ..writeln('Tool: ${toolCall.name}')
      ..writeln(
        'Status: ${AgentResponseFlowScreen._toolStatusLabel(toolCall)}',
      );

    if ((toolCall.id ?? '').isNotEmpty) {
      buffer.writeln('ID: ${toolCall.id}');
    }

    buffer
      ..writeln()
      ..writeln('Arguments:')
      ..write(encoder.convert(toolCall.arguments));

    final raw = toolCall.rawArguments?.trim();
    if (raw != null && raw.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln()
        ..writeln('Raw arguments:')
        ..write(raw);
    }

    return buffer.toString();
  }
}

class _FlowNode extends StatefulWidget {
  const _FlowNode({
    required this.icon,
    required this.label,
    required this.color,
    this.sublabel,
    this.details,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final Color color;
  final String? details;

  @override
  State<_FlowNode> createState() => _FlowNodeState();
}

class _FlowNodeState extends State<_FlowNode> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetails = (widget.details ?? '').trim().isNotEmpty;

    return InkWell(
      onTap: hasDetails
          ? () => setState(() => _isExpanded = !_isExpanded)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.color.withValues(alpha: 0.35)),
          color: Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(widget.icon, size: 20, color: widget.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: AppTheme.headingSmall.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (widget.sublabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.sublabel!,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: AppTheme.bodySmall.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasDetails)
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(48, 8, 8, 4),
                      child: SelectableText(
                        widget.details!.trim(),
                        style: AppTheme.bodySmall.copyWith(
                          fontSize: 11,
                          height: 1.45,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowDecision extends StatelessWidget {
  const _FlowDecision({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.question_diamond,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.headingSmall.copyWith(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Center(
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        text,
        style: AppTheme.bodySmall.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

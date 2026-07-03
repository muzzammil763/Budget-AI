import 'dart:math' as math;

Map<String, dynamic> localToolApprovalRequired({
  required String tool,
  required String title,
  required String command,
  required Map<String, dynamic> arguments,
  String consequence = '',
  bool sensitive = true,
  String commandType = 'destructive',
  Map<String, dynamic> extraRequestFields = const {},
}) {
  return {
    'tool': tool,
    'success': false,
    'approval_required': true,
    'approval_request': {
      'id':
          '${tool}_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}',
      'kind': 'local_tool',
      'tool': tool,
      'title': title,
      'command': command,
      'consequence': consequence,
      'arguments': arguments,
      'sensitive': sensitive,
      'command_type': commandType,
      'can_add_to_session': false,
      ...extraRequestFields,
    },
    'content': 'Waiting for $title approval.',
  };
}

/// Public entry point for OpenGate's AI tool APIs.
///
/// Tool implementation files live in focused subfolders under `tools/` and use
/// normal package imports instead of Dart `part` files.
library;

export 'core/tool_context.dart';
export 'core/tool_models.dart';
export 'modules/tool_modules.dart';
export 'registry/tool_registry.dart';

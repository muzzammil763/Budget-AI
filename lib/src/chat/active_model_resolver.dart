import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves which OpenAI model the app should use. There is no user-facing
/// picker: a single global row in Supabase (`ai_model_config`) lets the
/// model be switched from the backend without an app update. Any missing
/// row, unset value, unknown model id, or fetch error falls back to
/// [defaultModelId] so a bad config can never break the chat.
class ActiveModelResolver {
  ActiveModelResolver._();

  static final ActiveModelResolver instance = ActiveModelResolver._();

  static const String defaultModelId = 'gpt-5.6-luna';

  static const Set<String> supportedModelIds = {
    'gpt-5.6-luna',
    'gpt-5.6-terra',
    'gpt-5.6-sol',
    'gpt-5.5',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.4-nano',
    'gpt-4.1',
    'o3',
  };

  Future<String> resolve() async {
    try {
      final row = await Supabase.instance.client
          .from('ai_model_config')
          .select('active_model_id')
          .eq('id', 1)
          .maybeSingle();
      final activeModelId = row?['active_model_id'] as String?;
      if (activeModelId != null && supportedModelIds.contains(activeModelId)) {
        return activeModelId;
      }
    } catch (_) {
      // Network/RLS/schema issues all fall through to the hardcoded default.
    }
    return defaultModelId;
  }
}

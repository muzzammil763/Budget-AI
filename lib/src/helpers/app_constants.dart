/// Public runtime configuration for the Supabase client.
///
/// Supabase project URLs and publishable keys are intentionally safe to ship in
/// client applications. Authorization is enforced by user JWTs and RLS.
class AppConstants {
  AppConstants._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bzxsgpsacouvhxepfuca.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_njsGQE6DXIGGChyjO6Vv7w_SZKyBxzA',
  );

  /// Optional Edge Function region override for controlled latency tests.
  ///
  /// Empty keeps Supabase's automatic closest-region routing and failover.
  static const String supabaseFunctionRegion = String.fromEnvironment(
    'SUPABASE_FUNCTION_REGION',
    defaultValue: '',
  );

  static const String authConfirmRedirect = 'budgetai://auth/confirm';
  static const String passwordRecoveryRedirect =
      'budgetai://auth/reset-password';

  static String get openAIResponsesEndpoint =>
      '$supabaseUrl/functions/v1/openai-responses';
}

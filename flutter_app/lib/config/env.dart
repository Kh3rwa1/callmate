/// Runtime configuration.
///
/// Values are supplied at build time with `--dart-define` so nothing sensitive
/// is ever committed. Only the Supabase URL and its *public* anon key are
/// required — the voice provider's credentials live on the backend.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True when both values were supplied at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get apiBaseUrl => '$supabaseUrl/functions/v1/api';
}

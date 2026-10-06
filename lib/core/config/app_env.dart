/// Environment configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file=env/<env>.json`.
/// NOTHING secret belongs here: the app only ever knows our own backend URL.
/// Sarvam API keys live exclusively on the backend.
enum AppFlavor { dev, staging, prod }

class AppEnv {
  const AppEnv._();

  static const String _flavorRaw = String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev');

  /// Base URL of OUR backend (never Sarvam directly).
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Path on our backend that proxies Sarvam app-runtime requests and injects
  /// the X-API-Key header server-side. See backend/README.md.
  static const String sarvamProxyPath = String.fromEnvironment('SARVAM_PROXY_PATH', defaultValue: '/voice/sarvam-proxy/');

  /// Force mock/demo mode even if an API URL is configured.
  static const bool forceMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// Shows the demo control panel (simulate calls, notifications...).
  static const bool demoTools = bool.fromEnvironment('DEMO_TOOLS', defaultValue: true);

  static AppFlavor get flavor => switch (_flavorRaw) {
    'prod' => AppFlavor.prod,
    'staging' => AppFlavor.staging,
    _ => AppFlavor.dev,
  };

  /// Mock mode is used whenever no backend is configured.
  static bool get useMock => forceMock || apiBaseUrl.isEmpty;

  static bool get showDemoTools => demoTools && flavor != AppFlavor.prod;
}

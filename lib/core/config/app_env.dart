import 'package:flutter/foundation.dart';

/// Environment configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file=env/<env>.json`.
/// Supports Cloudflare backend proxying as well as Sarvam AI voice integration.
enum AppFlavor { dev, staging, prod }

class AppEnv {
  const AppEnv._();

  static const String _flavorRaw = String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev');

  /// Base URL of OUR backend.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Path on our backend that proxies Sarvam app-runtime requests.
  static const String sarvamProxyPath = String.fromEnvironment('SARVAM_PROXY_PATH', defaultValue: '/voice/sarvam-proxy/');

  /// Optional direct Sarvam configuration.
  static const String sarvamApiKey = String.fromEnvironment('SARVAM_API_KEY', defaultValue: '');
  static const String sarvamOrgId = String.fromEnvironment('SARVAM_ORG_ID', defaultValue: 'org_callpilot');
  static const String sarvamWorkspaceId = String.fromEnvironment('SARVAM_WORKSPACE_ID', defaultValue: 'ws_callpilot');
  static const String sarvamAppId = String.fromEnvironment('SARVAM_APP_ID', defaultValue: 'app_callpilot_voice');

  /// Force mock/demo mode ONLY if explicitly configured with USE_MOCK=true.
  static const bool forceMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  /// Shows the demo control panel.
  static const bool demoTools = bool.fromEnvironment('DEMO_TOOLS', defaultValue: false);

  static AppFlavor get flavor => switch (_flavorRaw) {
    'prod' => AppFlavor.prod,
    'staging' => AppFlavor.staging,
    _ => AppFlavor.dev,
  };

  /// Mock mode is ONLY used when explicitly forced with USE_MOCK=true.
  static bool get useMock => forceMock;

  /// Effective backend base URL with platform fallback (Android emulator 10.0.2.2 vs localhost).
  static String get effectiveApiBaseUrl {
    if (apiBaseUrl.isNotEmpty) return apiBaseUrl;
    if (kIsWeb) return 'http://127.0.0.1:8787';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8787';
    return 'http://127.0.0.1:8787';
  }

  static bool get showDemoTools => demoTools && flavor != AppFlavor.prod;
}


import 'package:flutter/foundation.dart';

/// Environment configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file=env/<env>.json`.
/// All Sarvam voice traffic goes through the backend proxy
/// ([sarvamProxyPath]); no third-party API keys are ever compiled into the app.
enum AppFlavor { dev, staging, prod }

class AppEnv {
  const AppEnv._();

  static const String _flavorRaw = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'dev',
  );

  /// Base URL of OUR backend.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Path on our backend that proxies Sarvam app-runtime requests.
  static const String sarvamProxyPath = String.fromEnvironment(
    'SARVAM_PROXY_PATH',
    defaultValue: '/voice/sarvam-proxy/',
  );

  /// Force mock/demo mode ONLY if explicitly configured with USE_MOCK=true.
  static const bool forceMock = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: false,
  );

  /// Shows the demo control panel.
  static const bool demoTools = bool.fromEnvironment(
    'DEMO_TOOLS',
    defaultValue: false,
  );

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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8787';
    }
    return 'http://127.0.0.1:8787';
  }

  static bool get showDemoTools => demoTools && flavor != AppFlavor.prod;

  /// Validates the backend configuration for a build.
  ///
  /// Returns `null` when the configuration is acceptable, or a human-readable
  /// reason why the app must not start. Only non-mock staging/prod builds are
  /// checked: they need an `https` [apiBaseUrl] that is not a placeholder
  /// (`example.com`).
  static String? configError({
    required AppFlavor flavor,
    required bool useMock,
    required String apiBaseUrl,
  }) {
    if (useMock || flavor == AppFlavor.dev) return null;
    final label = flavor.name;
    final url = apiBaseUrl.trim();
    if (url.isEmpty) {
      return 'API_BASE_URL is empty for the $label build. '
          'Set it in env/$label.json to your real backend URL.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'API_BASE_URL "$url" for the $label build must be an absolute '
          'https:// URL.';
    }
    final host = uri.host.toLowerCase();
    if (host == 'example.com' || host.endsWith('.example.com')) {
      return 'API_BASE_URL "$url" for the $label build is a placeholder. '
          'Replace it in env/$label.json with your real backend domain.';
    }
    return null;
  }

  /// Throws a [StateError] if the compiled-in configuration is not safe to
  /// start with (see [configError]). Call once at startup.
  static void ensureValid() {
    final error = configError(
      flavor: flavor,
      useMock: useMock,
      apiBaseUrl: apiBaseUrl,
    );
    if (error != null) {
      throw StateError('Invalid app configuration: $error');
    }
  }
}

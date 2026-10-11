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

  /// Offers phone + SMS OTP login next to Google. Off unless the backend has
  /// an SMS provider configured.
  static const bool phoneOtpLogin = bool.fromEnvironment(
    'PHONE_OTP_LOGIN',
    defaultValue: false,
  );

  /// Offers a "Demo account sign-in" link (the phone + OTP form) for app
  /// store reviewers. The backend's REVIEW_LOGIN_PHONE gets a fixed code
  /// without SMS; any other number still needs an SMS provider.
  static const bool demoLogin = bool.fromEnvironment(
    'DEMO_LOGIN',
    defaultValue: false,
  );

  /// Shows the demo control panel.
  static const bool demoTools = bool.fromEnvironment(
    'DEMO_TOOLS',
    defaultValue: false,
  );

  /// Public Terms of Service and Privacy Policy pages. Empty until they're
  /// published: the sign-in footer then shows plain text instead of links.
  static const String termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: '',
  );
  static const String privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: '',
  );

  /// Public "how to delete your account" page (Play Console data-deletion
  /// URL). Empty hides the link.
  static const String deleteAccountUrl = String.fromEnvironment(
    'DELETE_ACCOUNT_URL',
    defaultValue: '',
  );

  /// Where "Help & support" emails go.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'founder@olitun.in',
  );

  /// "Watch 1-minute video" on the Help sheet, one link per app language.
  /// Empty hides the option for that language.
  static const String helpVideoUrlEn = String.fromEnvironment(
    'HELP_VIDEO_URL_EN',
    defaultValue: '',
  );
  static const String helpVideoUrlHi = String.fromEnvironment(
    'HELP_VIDEO_URL_HI',
    defaultValue: '',
  );
  static const String helpVideoUrlBn = String.fromEnvironment(
    'HELP_VIDEO_URL_BN',
    defaultValue: '',
  );

  /// The help video for [langCode] ('en' / 'hi' / 'bn'), or null if that
  /// language has none configured (the option is then hidden).
  static String? helpVideoUrl(
    String langCode, {
    String en = helpVideoUrlEn,
    String hi = helpVideoUrlHi,
    String bn = helpVideoUrlBn,
  }) {
    final url = switch (langCode) {
      'hi' => hi,
      'bn' => bn,
      _ => en,
    }.trim();
    return url.isEmpty ? null : url;
  }

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

  /// The demo panel drives the mock backend, so it is useless (a dead-end
  /// screen) against a real API.
  static bool get showDemoTools =>
      demoTools && useMock && flavor != AppFlavor.prod;

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
    bool releaseMode = false,
  }) {
    if (useMock) return null;
    if (flavor == AppFlavor.dev) {
      // A release build without --dart-define-from-file would otherwise talk
      // to the emulator dev server over cleartext http.
      return releaseMode
          ? 'This release build has no APP_FLAVOR. Build it with '
                '--dart-define-from-file=env/prod.json.'
          : null;
    }
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

  /// Reason the compiled-in configuration is not safe to start with, or
  /// `null` (see [configError]). Checked once at startup.
  static String? startupError() => configError(
    flavor: flavor,
    useMock: useMock,
    apiBaseUrl: apiBaseUrl,
    releaseMode: kReleaseMode,
  );

  /// Throws a [StateError] if [startupError] reports a problem.
  static void ensureValid() {
    final error = startupError();
    if (error != null) {
      throw StateError('Invalid app configuration: $error');
    }
  }
}

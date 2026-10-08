import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Single place that initialises Firebase (FCM + Crashlytics).
///
/// Android reads its options from `google-services.json`, which the release
/// build requires (see android/app/build.gradle.kts). Returns `false` instead
/// of throwing so the app keeps working when Firebase is unavailable
/// (tests, web, dev builds without the file).
class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static Future<bool>? _flight;

  static Future<bool> ensureInitialized() => _flight ??= _init();

  static Future<bool> _init() async {
    if (kIsWeb) return false;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[firebase] not configured: $e');
      return false;
    }
  }

  @visibleForTesting
  static void reset() => _flight = null;
}

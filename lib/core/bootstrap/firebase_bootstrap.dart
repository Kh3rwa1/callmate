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
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: 'AIzaSyBTghmSF4_hxwzCyZzdmDqGG7oacjWuQI0',
              appId: '1:218247729126:web:cc9287b2ff7f6c92c81027',
              messagingSenderId: '218247729126',
              projectId: 'callpilot-app-c9b053',
              authDomain: 'callpilot-app-c9b053.firebaseapp.com',
              storageBucket: 'callpilot-app-c9b053.firebasestorage.app',
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[firebase] not configured: $e');
      return false;
    }
  }

  @visibleForTesting
  static void reset() => _flight = null;
}

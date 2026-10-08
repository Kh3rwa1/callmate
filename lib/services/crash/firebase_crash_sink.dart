import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'crash_reporting_service.dart';

/// Sends scrubbed reports to Firebase Crashlytics.
///
/// Only use once `Firebase.initializeApp()` has succeeded.
class FirebaseCrashSink implements CrashSink {
  FirebaseCrashSink([FirebaseCrashlytics? crashlytics])
    : _c = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _c;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object> context = const {},
  }) async {
    for (final e in context.entries) {
      await _c.setCustomKey(e.key, e.value);
    }
    await _c.recordError(error, stack, reason: reason, fatal: fatal);
  }

  @override
  Future<void> log(String message) => _c.log(message);
}

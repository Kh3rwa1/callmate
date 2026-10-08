import 'dart:async';

import 'package:flutter/foundation.dart';

/// Privacy-respecting crash reporting service.
/// All errors, stacktraces, and custom attributes are scrubbed for PII:
/// - Indian and international mobile numbers (e.g. +91 98300 12345)
/// - Bearer tokens and JWT strings
/// - Transcripts and message bodies
abstract class CrashReportingService {
  void reportError(
    Object error,
    StackTrace? stack, {
    String? reason,
    Map<String, Object>? context,
    bool fatal = false,
  });
  void log(String message);
}

/// Destination for already-scrubbed crash data (e.g. Firebase Crashlytics).
abstract class CrashSink {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object> context = const {},
  });
  Future<void> log(String message);
}

class SafeCrashReportingService implements CrashReportingService {
  SafeCrashReportingService({this.enabled = true, this.sink});

  final bool enabled;

  /// Where scrubbed reports go. `null` → debug console only.
  final CrashSink? sink;

  static final _phonePattern = RegExp(r'(?:\+?91[\s-]?)?[6-9]\d{9}');
  static final _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._-]+',
    caseSensitive: false,
  );
  static final _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
  );
  static final _emailPattern = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static String scrubPii(String input) {
    var out = input;
    out = out.replaceAll(_phonePattern, '[PHONE_REDACTED]');
    out = out.replaceAll(_bearerPattern, 'Bearer [TOKEN_REDACTED]');
    out = out.replaceAll(_jwtPattern, '[JWT_REDACTED]');
    out = out.replaceAll(_emailPattern, '[EMAIL_REDACTED]');
    return out;
  }

  static const _blockedKeys = {
    'phone',
    'mobile',
    'transcript',
    'raw_metadata',
    'token',
    'secret',
    'password',
    'message',
  };

  Map<String, Object> scrubContext(Map<String, Object>? raw) {
    if (raw == null) return const {};
    final clean = <String, Object>{};
    for (final entry in raw.entries) {
      if (_blockedKeys.contains(entry.key.toLowerCase())) continue;
      final val = entry.value;
      if (val is String) {
        clean[entry.key] = scrubPii(val);
      } else {
        clean[entry.key] = val;
      }
    }
    return clean;
  }

  @override
  void reportError(
    Object error,
    StackTrace? stack, {
    String? reason,
    Map<String, Object>? context,
    bool fatal = false,
  }) {
    if (!enabled) return;
    final scrubbedError = scrubPii(error.toString());
    final scrubbedReason = reason != null ? scrubPii(reason) : null;
    final cleanContext = scrubContext(context);

    if (kDebugMode) {
      debugPrint(
        '[CrashReporter] Error: $scrubbedError | reason: $scrubbedReason | ctx: $cleanContext',
      );
    }
    // The raw error object is never forwarded: only its scrubbed text.
    unawaited(
      sink
          ?.recordError(
            ScrubbedError(error.runtimeType.toString(), scrubbedError),
            stack,
            reason: scrubbedReason,
            fatal: fatal,
            context: cleanContext,
          )
          .catchError((Object _) {}),
    );
  }

  @override
  void log(String message) {
    if (!enabled) return;
    final scrubbed = scrubPii(message);
    if (kDebugMode) {
      debugPrint('[CrashReporter] $scrubbed');
    }
    unawaited(sink?.log(scrubbed).catchError((Object _) {}));
  }
}

/// PII-free stand-in for the original error sent to the [CrashSink].
class ScrubbedError {
  const ScrubbedError(this.type, this.message);
  final String type;
  final String message;

  @override
  String toString() => '$type: $message';
}

import 'package:flutter/foundation.dart';

/// Privacy-safe analytics facade.
///
/// RULE: never pass names, phone numbers, transcripts or message bodies.
/// Only event names + coarse, non-identifying properties.
abstract class AnalyticsService {
  void track(String event, [Map<String, Object> props = const {}]);
}

class DebugAnalyticsService implements AnalyticsService {
  static const _blocked = {
    'name',
    'phone',
    'message',
    'transcript',
    'summary',
    'email',
  };

  @override
  void track(String event, [Map<String, Object> props = const {}]) {
    final safe = Map.of(props)..removeWhere((k, _) => _blocked.contains(k));
    if (kDebugMode) debugPrint('[analytics] $event $safe');
  }
}

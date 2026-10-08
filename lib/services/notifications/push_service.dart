import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/bootstrap/firebase_bootstrap.dart';
import '../crash/crash_reporting_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate: nothing from the main isolate is set up here.
  try {
    await FirebaseBootstrap.ensureInitialized();
    // If the backend sends a `notification` block, the OS shows it itself.
    // Data-only messages have to be shown by us.
    if (message.notification == null) {
      await PushService.ensureLocalReady();
      await PushService.showLocal(message.data);
    }
  } catch (_) {
    // Never crash the background isolate over a notification.
  }
}

class PushService {
  PushService({
    required this.registerToken,
    required this.onRoute,
    this.onData,
    this.crash,
  });

  /// Registers the FCM token with our backend.
  final Future<void> Function(String token, String platform) registerToken;

  /// Opens an in-app route (only internal routes are forwarded).
  final void Function(String route) onRoute;

  /// Called with the data payload of every push received in the foreground,
  /// so open screens can refresh.
  final void Function(Map<String, dynamic> data)? onData;

  final CrashReportingService? crash;

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static const _channel = AndroidNotificationChannel(
    'callpilot_alerts',
    'Lead alerts',
    description: 'Hot leads, callbacks and follow-ups',
    importance: Importance.high,
  );

  final _subs = <StreamSubscription<dynamic>>[];
  Future<void>? _initFlight;
  String? _lastToken;

  String? get currentToken => _lastToken;

  /// Safe to call repeatedly (e.g. on every login): the work runs once per
  /// instance, so listeners are never doubled.
  Future<void> init() => _initFlight ??= _init();

  Future<void> _init() async {
    if (!await FirebaseBootstrap.ensureInitialized()) {
      crash?.log('push: Firebase unavailable, push notifications disabled');
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      await ensureLocalReady();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _safeRegister(token);
      _subs
        ..add(messaging.onTokenRefresh.listen(_safeRegister))
        ..add(FirebaseMessaging.onMessage.listen(handleForeground))
        ..add(
          FirebaseMessaging.onMessageOpenedApp.listen(
            (m) => _openRoute(m.data['route']),
          ),
        );
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openRoute(initial.data['route']);
    } catch (e, s) {
      crash?.reportError(e, s, reason: 'push init failed');
    }
  }

  /// Foreground push: refresh data, then show it as a local notification.
  @visibleForTesting
  Future<void> handleForeground(RemoteMessage m) async {
    onData?.call(m.data);
    try {
      await showLocal(
        m.data,
        title: m.notification?.title,
        body: m.notification?.body,
      );
    } catch (e, s) {
      crash?.reportError(e, s, reason: 'push showLocal failed');
    }
  }

  Future<void> _safeRegister(String token) async {
    _lastToken = token;
    try {
      await registerToken(token, 'android');
    } catch (_) {
      /* retried on next launch / token refresh */
    }
  }

  void _openRoute(Object? route) {
    if (route is String && route.startsWith('/')) {
      onRoute(route); // only internal routes
    }
  }

  /// Initialises the local-notification plugin and our channel. Needed in
  /// every isolate before [showLocal].
  static Future<void> ensureLocalReady() async {
    if (_localReady) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    _localReady = true;
  }

  static Future<void> showLocal(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) async {
    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title ?? data['title'] as String? ?? 'CallPilot',
      body: body ?? data['body'] as String? ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_notify',
        ),
      ),
      payload: data['route'] as String?,
    );
  }

  static Future<void> deleteToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}

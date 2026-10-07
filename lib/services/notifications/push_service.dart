import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  // If the backend sends a `notification` block, the OS shows it automatically.
  // If it's data-only, show it ourselves:
  if (message.notification == null) {
    await PushService.showLocal(message.data);
  }
}

class PushService {
  PushService({required this.registerToken, required this.onRoute});

  /// Wire to your existing API client, e.g. (t, p) => api.post('/devices', {...})
  final Future<void> Function(String token, String platform) registerToken;
  final void Function(String route) onRoute;

  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'callpilot_alerts',
    'Lead alerts',
    description: 'Hot leads, callbacks and follow-ups',
    importance: Importance.high,
  );

  StreamSubscription<String>? _tokenSub;
  String? _lastToken;

  String? get currentToken => _lastToken;

  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {
      // Firebase not configured yet (e.g. running unit tests or missing google-services.json)
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _safeRegister(token);
      _tokenSub = messaging.onTokenRefresh.listen(_safeRegister);

      FirebaseMessaging.onMessage.listen(
        (m) => showLocal(
          m.data,
          title: m.notification?.title,
          body: m.notification?.body,
        ),
      );
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _openRoute(m.data['route']),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openRoute(initial.data['route']);
    } catch (_) {
      // Graceful fallback when FCM services are unavailable
    }
  }

  Future<void> _safeRegister(String token) async {
    _lastToken = token;
    try {
      final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
      await registerToken(token, platform);
    } catch (_) {
      /* retry on next launch / refresh */
    }
  }

  void _openRoute(Object? route) {
    if (route is String && route.startsWith('/')) {
      onRoute(route); // only internal routes
    }
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

  Future<void> dispose() async => _tokenSub?.cancel();
}

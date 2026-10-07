import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/models/misc.dart';

/// Abstraction over remote push (FCM / APNs / other provider).
/// Production: backend sends a data message {title, body, route}; the provider
/// implementation forwards it to [NotificationService.present].
abstract class PushProvider {
  Future<String?> registerDevice();
  Stream<AppNotification> get onMessage;
}

/// Placeholder until FCM is configured (google-services.json / APNs key).
class NoopPushProvider implements PushProvider {
  @override
  Future<String?> registerDevice() async => null;
  @override
  Stream<AppNotification> get onMessage => const Stream.empty();
}

/// Presents notifications and routes taps to in-app deep links.
class NotificationService {
  NotificationService({PushProvider? push}) : push = push ?? NoopPushProvider();

  final PushProvider push;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  final _inApp = StreamController<AppNotification>.broadcast();
  bool _ready = false;
  String? _launchRoute;

  /// Routes to open when the user taps a notification.
  Stream<String> get taps => _taps.stream;

  /// Shown as an in-app banner when the app is in the foreground (and on web).
  Stream<AppNotification> get inApp => _inApp.stream;

  /// Route from a notification that cold-started the app.
  String? takeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  static const _channel = AndroidNotificationDetails(
    'ai_employee_actions',
    'AI employee updates',
    channelDescription: 'Hot leads, ready follow-ups and callbacks',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) _taps.add(p);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchRoute = launch?.notificationResponse?.payload;
      }
      push.onMessage.listen((n) => present(n));
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[notifications] init failed: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final a = await android?.requestNotificationsPermission();
      final i = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return (a ?? true) && (i ?? true);
    } catch (_) {
      return false;
    }
  }

  /// Show a notification. Always mirrored as an in-app banner so the owner
  /// sees it while the app is open.
  Future<void> present(AppNotification n, {bool system = true}) async {
    _inApp.add(n);
    if (!system || kIsWeb || !_ready) return;
    try {
      await _plugin.show(
        id: n.id.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body,
        payload: n.route,
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[notifications] show failed: $e');
    }
  }

  void simulateTap(String route) => _taps.add(route);
}

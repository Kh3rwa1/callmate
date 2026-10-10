import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Splits a backend title like "🔥 Hot lead detected" into its leading
/// emoji (rendered as a line icon) and the plain words.
(String, String) splitNotificationTitle(String title) {
  final chars = title.characters;
  if (chars.isEmpty) return ('', title);
  final first = chars.first;
  final isLetter = RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(first);
  if (isLetter) return ('', title);
  return (first, chars.skip(1).toString().trim());
}

/// The notification title without its emoji prefix.
String plainNotificationTitle(String title) => splitNotificationTitle(title).$2;

/// Title shown for [n]. Always our own plain words for the type ("Customer
/// ready to buy", not the backend's "Hot lead detected"), so the owner never
/// sees jargon. Calling updates keep the backend's English title, which names
/// the employee.
String notificationTitleFor(S s, AppNotification n) =>
    s.isEn &&
        (n.type == NotificationType.campaign ||
            n.type == NotificationType.newLead)
    ? plainNotificationTitle(n.title)
    : s.notificationTitle(n.type);

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
  NotificationService({PushProvider? push, this.strings})
    : push = push ?? NoopPushProvider();

  final PushProvider push;

  /// Strings in the owner's language, so the phone's notification tray says
  /// "Customer ready to buy" (in Hindi/Bengali too), never the backend's
  /// "Hot lead detected".
  final S Function()? strings;
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
    channelDescription: 'Customers ready to buy, messages and call backs',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
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
        title: strings == null
            ? plainNotificationTitle(n.title)
            : notificationTitleFor(strings!(), n),
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

import 'enums.dart';
import 'json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    this.actionLabel = 'Open',
    this.read = false,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;

  /// In-app deep link, e.g. `/followups/fu_1`.
  final String route;
  final String actionLabel;
  final bool read;
  final DateTime createdAt;

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    route: route,
    actionLabel: actionLabel,
    read: read ?? this.read,
    createdAt: createdAt,
  );

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: jStr(j, 'id'),
    type: NotificationType.parse(jStrN(j, 'type')),
    title: jStr(j, 'title'),
    body: jStr(j, 'body'),
    route: jStr(j, 'route', '/home'),
    actionLabel: jStr(j, 'action_label', 'Open'),
    read: jBool(j, 'read'),
    createdAt: jDate(j, 'created_at') ?? DateTime.now(),
  );
}

class Subscription {
  const Subscription({required this.planName, required this.includedMinutes, required this.renewsAt, this.priceInr = 0});
  final String planName;
  final int includedMinutes;
  final DateTime renewsAt;
  final int priceInr;

  factory Subscription.fromJson(Json j) => Subscription(
    planName: jStr(j, 'plan_name', 'Founding Plan'),
    includedMinutes: jInt(j, 'included_minutes'),
    renewsAt: jDate(j, 'renews_at') ?? DateTime.now(),
    priceInr: jInt(j, 'price_inr'),
  );
}

class Usage {
  const Usage({required this.subscription, required this.minutesUsed, required this.callsMade, this.ratePerMinuteInr = 6});
  final Subscription subscription;
  final int minutesUsed;
  final int callsMade;
  final int ratePerMinuteInr;

  int get minutesRemaining => (subscription.includedMinutes - minutesUsed).clamp(0, subscription.includedMinutes);
  double get ratio => subscription.includedMinutes == 0 ? 0 : minutesUsed / subscription.includedMinutes;

  Usage copyWith({int? minutesUsed, int? callsMade}) => Usage(
    subscription: subscription,
    minutesUsed: minutesUsed ?? this.minutesUsed,
    callsMade: callsMade ?? this.callsMade,
    ratePerMinuteInr: ratePerMinuteInr,
  );

  factory Usage.fromJson(Json j) => Usage(
    subscription: Subscription.fromJson(jObj(j, 'subscription') ?? const {}),
    minutesUsed: jInt(j, 'minutes_used'),
    callsMade: jInt(j, 'calls_made'),
    ratePerMinuteInr: jInt(j, 'rate_per_minute_inr', 6),
  );
}

/// "What happened today?" – computed server-side in production.
class DailySummary {
  const DailySummary({
    required this.leads,
    required this.connected,
    required this.interested,
    required this.hot,
    required this.callsToday,
    required this.followUpsReady,
    required this.callbacksToday,
    required this.newLeadsReady,
    this.activity = const [],
  });
  final int leads;
  final int connected;
  final int interested;
  final int hot;
  final int callsToday;
  final int followUpsReady;
  final int callbacksToday;
  final int newLeadsReady;
  final List<ActivityItem> activity;
}

class ActivityItem {
  const ActivityItem({required this.emoji, required this.text, required this.at, this.route});
  final String emoji;
  final String text;
  final DateTime at;
  final String? route;
}

/// Simple paginated page.
class Page<T> {
  const Page({required this.items, required this.hasMore, this.nextCursor});
  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
}

class VoiceTestSession {
  const VoiceTestSession({
    required this.sessionToken,
    required this.orgId,
    required this.workspaceId,
    required this.appId,
    required this.proxyBaseUrl,
    this.version,
    this.agentVariables = const {},
    this.userIdentifier = 'owner',
    this.greetingText,
    this.greetingAudioBase64,
  });

  /// Short-lived token for OUR proxy (not a Sarvam key).
  final String sessionToken;
  final String orgId;
  final String workspaceId;
  final String appId;
  final String proxyBaseUrl;
  final int? version;
  final Map<String, dynamic> agentVariables;
  final String userIdentifier;
  final String? greetingText;
  final String? greetingAudioBase64;

  factory VoiceTestSession.fromJson(Json j) => VoiceTestSession(
    sessionToken: jStr(j, 'session_token'),
    orgId: jStr(j, 'org_id'),
    workspaceId: jStr(j, 'workspace_id'),
    appId: jStr(j, 'app_id'),
    proxyBaseUrl: jStr(j, 'proxy_base_url'),
    version: jIntN(j, 'version'),
    agentVariables: jObj(j, 'agent_variables') ?? const {},
    userIdentifier: jStr(j, 'user_identifier', 'owner'),
    greetingText: jStrN(j, 'greeting_text'),
    greetingAudioBase64: jStrN(j, 'greeting_audio_base64'),
  );
}

class VoiceChatReply {
  const VoiceChatReply({required this.reply, this.audioBase64});
  final String reply;
  final String? audioBase64;

  factory VoiceChatReply.fromJson(Json j) => VoiceChatReply(
    reply: jStr(j, 'reply'),
    audioBase64: jStrN(j, 'audio_base64'),
  );
}

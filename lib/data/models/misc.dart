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

/// Billing state of the plan (server `plan_status`).
enum PlanStatus {
  trial,
  active,
  pastDue,
  cancelled;

  static PlanStatus parse(String? v) => switch (v) {
    'trial' => trial,
    'past_due' => pastDue,
    'cancelled' => cancelled,
    _ => active,
  };

  /// Calls and campaigns are blocked until the owner pays.
  bool get blocksCalling => this == pastDue || this == cancelled;
}

class Subscription {
  const Subscription({
    required this.planName,
    required this.includedMinutes,
    required this.renewsAt,
    this.priceInr = 0,
    this.planId = 'starter',
    this.status = PlanStatus.active,
    this.currentPeriodEnd,
  });
  final String planName;
  final int includedMinutes;
  final DateTime renewsAt;
  final int priceInr;

  /// `trial` or a paid plan id (`starter`).
  final String planId;
  final PlanStatus status;

  /// End of the paid period (UTC); null for trials and legacy plans.
  final DateTime? currentPeriodEnd;

  bool get isTrial => status == PlanStatus.trial;

  Subscription copyWith({
    String? planName,
    int? includedMinutes,
    int? priceInr,
    String? planId,
    PlanStatus? status,
    DateTime? currentPeriodEnd,
  }) => Subscription(
    planName: planName ?? this.planName,
    includedMinutes: includedMinutes ?? this.includedMinutes,
    renewsAt: currentPeriodEnd ?? renewsAt,
    priceInr: priceInr ?? this.priceInr,
    planId: planId ?? this.planId,
    status: status ?? this.status,
    currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
  );

  factory Subscription.fromJson(Json j) => Subscription(
    planName: jStr(j, 'plan_name', 'Founding Plan'),
    includedMinutes: jInt(j, 'included_minutes'),
    renewsAt: jDate(j, 'renews_at') ?? DateTime.now(),
    priceInr: jInt(j, 'price_inr'),
    planId: jStr(j, 'plan_id', 'starter'),
    status: PlanStatus.parse(jStrN(j, 'plan_status')),
    currentPeriodEnd: jDate(j, 'current_period_end'),
  );
}

/// What "Upgrade" / "Renew" buys.
class CheckoutPlan {
  const CheckoutPlan({
    this.planId = 'starter',
    this.name = 'Starter',
    this.priceInr = 4999,
    this.includedMinutes = 1000,
  });
  final String planId;
  final String name;
  final int priceInr;
  final int includedMinutes;

  factory CheckoutPlan.fromJson(Json j) => CheckoutPlan(
    planId: jStr(j, 'plan_id', 'starter'),
    name: jStr(j, 'name', 'Starter'),
    priceInr: jInt(j, 'price_inr', 4999),
    includedMinutes: jInt(j, 'included_minutes', 1000),
  );
}

class Usage {
  const Usage({
    required this.subscription,
    required this.minutesUsed,
    required this.callsMade,
    this.ratePerMinuteInr = 6,
    this.checkoutPlan = const CheckoutPlan(),
  });
  final Subscription subscription;
  final int minutesUsed;
  final int callsMade;
  final int ratePerMinuteInr;
  final CheckoutPlan checkoutPlan;

  int get minutesRemaining => (subscription.includedMinutes - minutesUsed)
      .clamp(0, subscription.includedMinutes);
  double get ratio => subscription.includedMinutes == 0
      ? (subscription.isTrial ? 1 : 0)
      : minutesUsed / subscription.includedMinutes;

  /// Trial with at most 20% (or 5 minutes) left, but not yet used up.
  bool get trialLow =>
      subscription.isTrial &&
      minutesRemaining > 0 &&
      (minutesRemaining <= 5 ||
          minutesRemaining <= subscription.includedMinutes * 0.2);

  /// No minutes left to call with.
  bool get exhausted => minutesRemaining <= 0;

  Usage copyWith({
    int? minutesUsed,
    int? callsMade,
    Subscription? subscription,
  }) => Usage(
    subscription: subscription ?? this.subscription,
    minutesUsed: minutesUsed ?? this.minutesUsed,
    callsMade: callsMade ?? this.callsMade,
    ratePerMinuteInr: ratePerMinuteInr,
    checkoutPlan: checkoutPlan,
  );

  factory Usage.fromJson(Json j) => Usage(
    subscription: Subscription.fromJson(jObj(j, 'subscription') ?? const {}),
    minutesUsed: jInt(j, 'minutes_used'),
    callsMade: jInt(j, 'calls_made'),
    ratePerMinuteInr: jInt(j, 'rate_per_minute_inr', 6),
    checkoutPlan: CheckoutPlan.fromJson(jObj(j, 'checkout_plan') ?? const {}),
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

/// Period the home results card covers (`GET /dashboard/results?range=`).
enum ResultsRange {
  today('today'),
  week('week'),
  month('month');

  const ResultsRange(this.wire);
  final String wire;
}

/// What the AI employee achieved in one period. The owner's own test calls
/// never count.
class PeriodResults {
  const PeriodResults({
    this.enquiries = 0,
    this.calls = 0,
    this.callsConnected = 0,
    this.interested = 0,
    this.readyToBuy = 0,
    this.followUpsSent = 0,
    this.estimatedValueInr,
  });

  /// New leads added in the period.
  final int enquiries;
  final int calls;
  final int callsConnected;

  /// Distinct leads scored warm or hot on a connected call.
  final int interested;

  /// Distinct leads scored hot on a connected call.
  final int readyToBuy;

  /// WhatsApp follow-ups the owner sent.
  final int followUpsSent;

  /// readyToBuy × average sale value; null until the owner sets that value.
  final int? estimatedValueInr;

  factory PeriodResults.fromJson(Json j) => PeriodResults(
    enquiries: jInt(j, 'enquiries'),
    calls: jInt(j, 'calls'),
    callsConnected: jInt(j, 'calls_connected'),
    interested: jInt(j, 'interested'),
    readyToBuy: jInt(j, 'ready_to_buy'),
    followUpsSent: jInt(j, 'followups_sent'),
    estimatedValueInr: jIntN(j, 'estimated_value_inr'),
  );
}

/// `GET /dashboard/results`: the current period plus the one before it.
class ResultsSummary {
  const ResultsSummary({
    required this.range,
    required this.current,
    this.previous = const PeriodResults(),
    this.avgDealValueInr,
    this.hasCalls = false,
  });

  final ResultsRange range;
  final PeriodResults current;
  final PeriodResults previous;
  final int? avgDealValueInr;

  /// Whether the AI has ever called a customer (else Home offers a test call).
  final bool hasCalls;

  factory ResultsSummary.fromJson(Json j) => ResultsSummary(
    range: ResultsRange.values.firstWhere(
      (r) => r.wire == jStrN(j, 'range'),
      orElse: () => ResultsRange.week,
    ),
    current: PeriodResults.fromJson(j),
    previous: PeriodResults.fromJson(jObj(j, 'previous') ?? const {}),
    avgDealValueInr: jIntN(j, 'avg_deal_value_inr'),
    hasCalls: jBool(j, 'has_calls'),
  );
}

/// `GET/POST /agent/test-call`: the owner's number and test calls left today.
class OwnerTestCallInfo {
  const OwnerTestCallInfo({
    this.phone,
    this.remainingToday = 0,
    this.limit = 3,
  });
  final String? phone;
  final int remainingToday;
  final int limit;

  factory OwnerTestCallInfo.fromJson(Json j) => OwnerTestCallInfo(
    phone: jStrN(j, 'phone'),
    remainingToday: jInt(j, 'remaining_today'),
    limit: jInt(j, 'limit', 3),
  );
}

class ActivityItem {
  const ActivityItem({
    required this.emoji,
    required this.text,
    required this.at,
    this.route,
  });
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
    this.sessionId,
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

  /// Server-side session row; ended via [VoiceSessionRepository.endTestSession]
  /// so it stops counting against the business's concurrent-session cap.
  final String? sessionId;

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
    sessionId: jStrN(j, 'session_id'),
  );
}

class VoiceChatReply {
  const VoiceChatReply({
    required this.reply,
    this.audioBase64,
    this.conversationId,
  });
  final String reply;
  final String? audioBase64;
  final String? conversationId;

  factory VoiceChatReply.fromJson(Json j) => VoiceChatReply(
    reply: jStr(j, 'reply'),
    audioBase64: jStrN(j, 'audio_base64'),
    conversationId: jStrN(j, 'conversation_id'),
  );
}

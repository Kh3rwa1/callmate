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

/// `GET /referrals`: the business's referral code, share link and results.
class ReferralSummary {
  const ReferralSummary({
    required this.code,
    required this.link,
    this.bonusMinutes = 200,
    this.signedUp = 0,
    this.rewarded = 0,
    this.minutesEarned = 0,
  });
  final String code;
  final String link;

  /// Minutes each side gets when an invited business makes its first payment.
  final int bonusMinutes;

  /// Businesses that signed up with this code.
  final int signedUp;

  /// Of those, how many have paid (both sides rewarded).
  final int rewarded;
  final int minutesEarned;

  factory ReferralSummary.fromJson(Json j) => ReferralSummary(
    code: jStr(j, 'code'),
    link: jStr(j, 'link'),
    bonusMinutes: jInt(j, 'bonus_minutes', 200),
    signedUp: jInt(j, 'signed_up'),
    rewarded: jInt(j, 'rewarded'),
    minutesEarned: jInt(j, 'minutes_earned'),
  );
}

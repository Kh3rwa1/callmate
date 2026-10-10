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
    this.annual = false,
    this.annualUntil,
    this.topupMinutes = 0,
    this.bonusMinutes = 0,
  });
  final String planName;

  /// This period's plan minutes (without [topupMinutes] / [bonusMinutes]).
  final int includedMinutes;
  final DateTime renewsAt;
  final int priceInr;

  /// `trial` or a paid plan id (`starter`, `growth`).
  final String planId;
  final PlanStatus status;

  /// End of the paid period (UTC); null for trials and legacy plans.
  final DateTime? currentPeriodEnd;

  /// Paid yearly: minutes are re-granted every month until [annualUntil].
  final bool annual;
  final DateTime? annualUntil;

  /// Extra minutes bought this period (valid until the period ends).
  final int topupMinutes;

  /// Bonus minutes (referrals…); kept across renewals, used last.
  final int bonusMinutes;

  /// Everything callable this period: plan + top-up + bonus.
  int get totalMinutes => includedMinutes + topupMinutes + bonusMinutes;

  bool get isTrial => status == PlanStatus.trial;

  Subscription copyWith({
    String? planName,
    int? includedMinutes,
    int? priceInr,
    String? planId,
    PlanStatus? status,
    DateTime? currentPeriodEnd,
    bool? annual,
    DateTime? annualUntil,
    int? topupMinutes,
    int? bonusMinutes,
  }) => Subscription(
    bonusMinutes: bonusMinutes ?? this.bonusMinutes,
    annual: annual ?? this.annual,
    annualUntil: annualUntil ?? this.annualUntil,
    topupMinutes: topupMinutes ?? this.topupMinutes,
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
    annual: jStrN(j, 'billing_cycle') == 'annual',
    annualUntil: jDate(j, 'annual_until'),
    topupMinutes: jInt(j, 'topup_minutes'),
    bonusMinutes: jInt(j, 'bonus_minutes'),
  );
}

/// One thing checkout sells (server catalogue item): a monthly or annual
/// plan, or a top-up pack. Prices are whole rupees; [totalInr] includes GST
/// and is what the payment page charges.
class CheckoutPlan {
  const CheckoutPlan({
    this.planId = 'starter',
    this.name = 'Starter',
    this.priceInr = 4999,
    this.gstInr = 900,
    this.totalInr = 5899,
    this.includedMinutes = 1000,
    this.kind = 'plan',
    this.months = 1,
  });
  final String planId;
  final String name;

  /// Price before GST.
  final int priceInr;
  final int gstInr;
  final int totalInr;

  /// Plans: minutes per month. Top-ups: minutes added once.
  final int includedMinutes;

  /// `plan` (monthly), `annual` or `topup`.
  final String kind;

  /// Monthly grants bought: 1, 12 (annual) or 0 (top-up).
  final int months;

  bool get isAnnual => kind == 'annual';
  bool get isTopup => kind == 'topup';

  /// The monthly plan this item belongs to (`starter_annual` → `starter`).
  String get basePlanId => planId.replaceFirst('_annual', '');

  factory CheckoutPlan.fromJson(Json j) {
    final price = jInt(j, 'price_inr', 4999);
    final gst = jInt(j, 'gst_inr', (price * 0.18).round());
    return CheckoutPlan(
      planId: jStr(j, 'plan_id', 'starter'),
      name: jStr(j, 'name', 'Starter'),
      priceInr: price,
      gstInr: gst,
      totalInr: jInt(j, 'total_inr', price + gst),
      includedMinutes: jInt(j, 'included_minutes', 1000),
      kind: jStr(j, 'kind', 'plan'),
      months: jInt(j, 'months', 1),
    );
  }

  /// The catalogue an older backend (no `plans` / `topups`) sells.
  static const defaultPlans = [
    CheckoutPlan(),
    CheckoutPlan(
      planId: 'growth',
      name: 'Growth',
      priceInr: 11999,
      gstInr: 2160,
      totalInr: 14159,
      includedMinutes: 3000,
    ),
    CheckoutPlan(
      planId: 'starter_annual',
      name: 'Starter (annual)',
      priceInr: 49990,
      gstInr: 8998,
      totalInr: 58988,
      kind: 'annual',
      months: 12,
    ),
    CheckoutPlan(
      planId: 'growth_annual',
      name: 'Growth (annual)',
      priceInr: 119990,
      gstInr: 21598,
      totalInr: 141588,
      includedMinutes: 3000,
      kind: 'annual',
      months: 12,
    ),
  ];

  static const defaultTopups = [
    CheckoutPlan(
      planId: 'topup_250',
      name: '250 extra minutes',
      priceInr: 1499,
      gstInr: 270,
      totalInr: 1769,
      includedMinutes: 250,
      kind: 'topup',
      months: 0,
    ),
    CheckoutPlan(
      planId: 'topup_1000',
      name: '1000 extra minutes',
      priceInr: 5499,
      gstInr: 990,
      totalInr: 6489,
      includedMinutes: 1000,
      kind: 'topup',
      months: 0,
    ),
  ];
}

class Usage {
  const Usage({
    required this.subscription,
    required this.minutesUsed,
    required this.callsMade,
    this.ratePerMinuteInr = 6,
    this.checkoutPlan = const CheckoutPlan(),
    this.plans = CheckoutPlan.defaultPlans,
    this.topups = CheckoutPlan.defaultTopups,
    bool? canBuyTopup,
  }) : _canBuyTopup = canBuyTopup;
  final Subscription subscription;
  final int minutesUsed;
  final int callsMade;
  final int ratePerMinuteInr;
  final CheckoutPlan checkoutPlan;

  /// Monthly and annual plans the plan picker offers.
  final List<CheckoutPlan> plans;

  /// Extra-minute packs (only buyable on an active plan).
  final List<CheckoutPlan> topups;
  final bool? _canBuyTopup;

  /// Top-ups extend an active paid plan only.
  bool get canBuyTopup =>
      (_canBuyTopup ?? true) &&
      subscription.status == PlanStatus.active &&
      topups.isNotEmpty;

  /// Plan + top-up + bonus minutes left (same rule as the server's
  /// `minutes_remaining`).
  int get minutesRemaining => (subscription.totalMinutes - minutesUsed).clamp(
    0,
    subscription.totalMinutes,
  );
  double get ratio => subscription.totalMinutes == 0
      ? (subscription.isTrial ? 1 : 0)
      : (minutesUsed / subscription.totalMinutes).clamp(0, 1);

  /// Trial with at most 20% (or 5 minutes) left, but not yet used up.
  bool get trialLow =>
      subscription.isTrial &&
      minutesRemaining > 0 &&
      (minutesRemaining <= 5 ||
          minutesRemaining <= subscription.totalMinutes * 0.2);

  /// Active paid plan with at most 10% (or 30 minutes) left, not used up.
  bool get paidLow =>
      subscription.status == PlanStatus.active &&
      subscription.totalMinutes > 0 &&
      minutesRemaining > 0 &&
      (minutesRemaining <= 30 ||
          minutesRemaining <= subscription.totalMinutes * 0.1);

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
    plans: plans,
    topups: topups,
    canBuyTopup: _canBuyTopup,
  );

  factory Usage.fromJson(Json j) {
    final plans = jList(j, 'plans', CheckoutPlan.fromJson);
    final topups = jList(j, 'topups', CheckoutPlan.fromJson);
    final legacy = !j.containsKey('plans');
    return Usage(
      subscription: Subscription.fromJson(jObj(j, 'subscription') ?? const {}),
      minutesUsed: jInt(j, 'minutes_used'),
      callsMade: jInt(j, 'calls_made'),
      ratePerMinuteInr: jInt(j, 'rate_per_minute_inr', 6),
      checkoutPlan: CheckoutPlan.fromJson(jObj(j, 'checkout_plan') ?? const {}),
      plans: legacy ? CheckoutPlan.defaultPlans : plans,
      // An older backend cannot sell top-ups.
      topups: legacy ? const [] : topups,
      canBuyTopup: j['can_buy_topup'] is bool
          ? j['can_buy_topup'] as bool
          : null,
    );
  }
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

import 'dart:async';
import 'dart:math';

import '../../../core/utils/phone.dart';
import '../../models/ai_output.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../templates/templates.dart';
import 'mock_brain.dart';

/// In-memory demo backend.
///
/// Behaves like our real backend: owns campaigns, "places" calls, receives a
/// (simulated) Sarvam completed-call webhook, normalises the structured AI
/// output into Call / Lead / FollowUp / Callback, and pushes events.
class MockBackend implements BackendEvents {
  MockBackend({int seed = 7, Business? business, Agent? agent}) : _rnd = Random(seed) {
    brain = MockBrain(_rnd);
    this.business = business ?? _defaultBusiness;
    this.agent = agent ?? _defaultAgent;
    _seed();
  }

  final Random _rnd;
  late final MockBrain brain;
  final _events = StreamController<BackendEvent>.broadcast();

  @override
  Stream<BackendEvent> get stream => _events.stream;

  late Business business;
  late Agent agent;
  final Map<String, Lead> leads = {};
  final List<Call> calls = [];
  final Map<String, FollowUp> followUps = {};
  final Map<String, Callback> callbacks = {};
  final List<AppNotification> notifications = [];
  final Map<String, Campaign> campaigns = {};
  final List<KnowledgeSource> knowledge = [];
  late Usage usage;
  final List<ActivityItem> activity = [];
  int _id = 1000;
  Timer? _campaignTimer;

  String _nextId(String p) => '${p}_${_id++}';

  static const _defaultBusiness = Business(
    id: 'biz_1',
    name: 'ABC Coaching Centre',
    category: BusinessCategory.coaching,
    address: '12 Park Street, Kolkata',
    offerings: ['NEET', 'JEE Main', 'WBJEE', 'Class 10 Boards', 'Class 12 Science'],
    fees: 'NEET ₹52,000/yr · JEE ₹56,000/yr · Boards from ₹24,000/yr',
    openingHours: 'Mon–Sat, 9 AM – 8 PM',
    location: 'Park Street, Kolkata',
    whatsappNumber: '+91 98300 12345',
    counsellorNumber: '+91 98300 54321',
    ownerName: 'Dulor',
  );

  static final _defaultAgent = Agent(
    id: 'agent_1',
    name: coachingAgentTemplate.defaultName,
    role: coachingAgentTemplate.role,
    status: AgentStatus.active,
    templateId: coachingAgentTemplate.id,
    languages: coachingAgentTemplate.languages,
    goal: coachingAgentTemplate.goal,
    capabilities: coachingAgentTemplate.capabilities,
    transferNumber: '+91 98300 54321',
  );

  // ------------------------------------------------------------------ seed
  void _seed() {
    final now = DateTime.now();
    usage = Usage(
      subscription: Subscription(
        planName: 'Founding Plan',
        includedMinutes: 1000,
        renewsAt: DateTime(now.year, now.month + 1, 1),
        priceInr: 4999,
      ),
      minutesUsed: 642,
      callsMade: 0,
    );

    knowledge.addAll([
      KnowledgeSource(
        id: 'kn_1',
        type: KnowledgeType.pdf,
        title: 'Admission Brochure',
        detail: 'brochure_2025.pdf · 8 pages',
        status: KnowledgeStatus.ready,
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      KnowledgeSource(
        id: 'kn_2',
        type: KnowledgeType.pdf,
        title: 'Course Fees',
        detail: 'fees_2025.pdf · 2 pages',
        status: KnowledgeStatus.ready,
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      KnowledgeSource(
        id: 'kn_3',
        type: KnowledgeType.faq,
        title: 'FAQ',
        detail: '14 questions',
        status: KnowledgeStatus.ready,
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      KnowledgeSource(
        id: 'kn_4',
        type: KnowledgeType.website,
        title: 'Website',
        detail: 'abccoaching.in',
        status: KnowledgeStatus.ready,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      KnowledgeSource(
        id: 'kn_5',
        type: KnowledgeType.centreInfo,
        title: 'Centre Information',
        detail: 'Timings, address, counsellor',
        status: KnowledgeStatus.ready,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    ]);

    // Hero leads (stable for demos)
    final heroes = <(String, String, String, String, LeadTemperature?, int?)>[
      ('Rahul Kumar', '9830011122', 'NEET', 'Evening', LeadTemperature.hot, 87),
      ('Priya Das', '9831022233', 'JEE Main', 'Weekend', LeadTemperature.hot, 82),
      ('Ankit Singh', '9874033344', 'WBJEE', 'Evening', LeadTemperature.warm, 64),
      ('Suman Murmu', '9007044455', 'Class 12 Science', 'Morning', LeadTemperature.warm, 58),
      ('Sneha Chatterjee', '9433055566', 'NEET', 'Morning', LeadTemperature.hot, 91),
      ('Arif Khan', '9123066677', 'JEE Advanced', 'Evening', LeadTemperature.cold, 22),
    ];

    final dayStart = DateTime(now.year, now.month, now.day, 9, 30);
    final windowMinutes = max(60, now.difference(dayStart).inMinutes);
    DateTime callTime(int i, int n) => now.subtract(Duration(minutes: ((i + 1) / (n + 1) * windowMinutes).round()));

    var idx = 0;
    const calledCount = 110;
    for (final h in heroes) {
      final lead = _makeLead(h.$1, h.$2, h.$3, h.$4, now.subtract(Duration(hours: 3 + idx)));
      leads[lead.id] = lead;
      _runCall(lead, temperature: h.$5, forcedScore: h.$6, at: callTime(idx, calledCount), connected: true, quiet: true);
      idx++;
    }

    // Distribution for the remaining called leads: ~68% connected.
    final hotTarget = 12 - heroes.where((h) => h.$5 == LeadTemperature.hot).length;
    final warmTarget = 22 - heroes.where((h) => h.$5 == LeadTemperature.warm).length;
    var hot = 0, warm = 0;
    for (; idx < calledCount; idx++) {
      final lead = _makeLead(
        _randomName(),
        _randomPhone(),
        brain.pick(mockCourses).name,
        null,
        now.subtract(Duration(minutes: 30 + _rnd.nextInt(400))),
      );
      leads[lead.id] = lead;
      final connected = _rnd.nextDouble() < 0.66;
      LeadTemperature? t;
      if (connected) {
        if (hot < hotTarget && _rnd.nextDouble() < 0.25) {
          t = LeadTemperature.hot;
          hot++;
        } else if (warm < warmTarget && _rnd.nextDouble() < 0.45) {
          t = LeadTemperature.warm;
          warm++;
        } else {
          t = LeadTemperature.cold;
        }
      }
      _runCall(lead, temperature: t, at: callTime(idx, calledCount), connected: connected, quiet: true);
    }

    // Fresh leads waiting to be called.
    for (var i = 0; i < 37; i++) {
      final lead = _makeLead(
        _randomName(),
        _randomPhone(),
        brain.pick(mockCourses).name,
        null,
        now.subtract(Duration(minutes: 5 + _rnd.nextInt(240))),
      );
      leads[lead.id] = lead;
    }

    // Older follow-ups were already handled – keep ~18 pending.
    final pending = followUps.values.where((f) => f.isPending).toList()..sort((a, b) => (b.scoreValue ?? 0).compareTo(a.scoreValue ?? 0));
    for (final f in pending.skip(18)) {
      followUps[f.id] = f.copyWith(status: FollowUpStatus.opened, openedAt: f.createdAt.add(const Duration(minutes: 20)));
    }

    usage = usage.copyWith(callsMade: calls.length);
    agent = agent.copyWith(callsToday: calls.length);

    final hotLeads = leads.values.where((l) => l.isHot).length;
    final rahul = leads.values.firstWhere((l) => l.name == 'Rahul Kumar');
    final priya = leads.values.firstWhere((l) => l.name == 'Priya Das');
    notifications.addAll([
      AppNotification(
        id: 'n_1',
        type: NotificationType.hotLead,
        title: '🔥 Hot lead detected',
        body: '${agent.name} completed a call with Rahul. Lead score: 87.',
        route: '/followups/${followUpForLead(rahul.id)?.id ?? ''}',
        actionLabel: 'Review Follow-up',
        createdAt: now.subtract(const Duration(minutes: 42)),
      ),
      AppNotification(
        id: 'n_2',
        type: NotificationType.followUpReady,
        title: '💬 Follow-up ready',
        body: 'Your AI employee prepared a WhatsApp message for Priya.',
        route: '/followups/${followUpForLead(priya.id)?.id ?? ''}',
        createdAt: now.subtract(const Duration(hours: 1, minutes: 10)),
      ),
      AppNotification(
        id: 'n_3',
        type: NotificationType.callback,
        title: '📅 Callback',
        body: 'Rahul asked to speak tomorrow at 6 PM.',
        route: '/leads/${rahul.id}',
        actionLabel: 'View lead',
        createdAt: now.subtract(const Duration(minutes: 41)),
        read: true,
      ),
    ]);

    activity
      ..clear()
      ..addAll([
        ActivityItem(
          emoji: '📞',
          text: '${agent.name} completed ${calls.length} calls',
          at: now.subtract(const Duration(minutes: 5)),
          route: '/calls',
        ),
        ActivityItem(
          emoji: '🔥',
          text: '$hotLeads leads became hot',
          at: now.subtract(const Duration(minutes: 18)),
          route: '/leads?filter=hot',
        ),
        ActivityItem(
          emoji: '📅',
          text: '${callbacks.length} callbacks scheduled',
          at: now.subtract(const Duration(minutes: 40)),
          route: '/callbacks',
        ),
        ActivityItem(
          emoji: '💬',
          text: '${followUps.values.where((f) => f.isPending).length} WhatsApp follow-ups drafted',
          at: now.subtract(const Duration(hours: 1)),
          route: '/followups',
        ),
      ]);
  }

  String _randomName() => '${brain.pick(mockFirstNames)} ${brain.pick(mockLastNames)}';
  String _randomPhone() => '${brain.pick(['98', '97', '90', '91', '83', '70', '62'])}${(10000000 + _rnd.nextInt(89999999))}';

  Lead _makeLead(String name, String phone, String course, String? batch, DateTime created, {String? source}) => Lead(
    id: _nextId('lead'),
    businessId: business.id,
    name: name,
    phone: PhoneUtils.normalize(phone) ?? phone,
    source: source ?? brain.pick(mockSources),
    courseInterest: course,
    preferredBatch: batch,
    status: LeadStatus.newLead,
    createdAt: created,
    updatedAt: created,
  );

  // ------------------------------------------------------------ call engine

  /// Simulates: place call → Sarvam completed-call webhook → normalise.
  Call _runCall(
    Lead lead, {
    LeadTemperature? temperature,
    int? forcedScore,
    DateTime? at,
    bool connected = true,
    String? campaignId,
    bool quiet = false,
  }) {
    final start = at ?? DateTime.now();
    final callId = _nextId('call');
    final interactionId = 'int_${_rnd.nextInt(1 << 31).toRadixString(16)}';

    if (!connected) {
      final status = _rnd.nextDouble() < 0.8 ? CallStatus.noAnswer : CallStatus.busy;
      final call = Call(
        id: callId,
        leadId: lead.id,
        leadName: lead.name,
        leadPhone: lead.phone,
        campaignId: campaignId,
        agentId: agent.id,
        status: status,
        startedAt: start,
        endedAt: start.add(const Duration(seconds: 30)),
        nextAction: NextAction.retryCall,
        outcome: status == CallStatus.busy ? 'Line busy' : 'Did not pick up',
        interactionId: interactionId,
        rawMetadata: {'connectivity_status': status.wire, 'provider': 'mock'},
      );
      calls.insert(0, call);
      leads[lead.id] = lead.copyWith(status: LeadStatus.noAnswer, lastCallId: callId, nextAction: NextAction.retryCall, updatedAt: start);
      return call;
    }

    final t = temperature ?? LeadTemperature.cold;
    final out = brain.think(lead: lead, temperature: t, business: business, agent: agent, forcedScore: forcedScore);
    return _ingestWebhook(lead, out, callId: callId, interactionId: interactionId, start: start, campaignId: campaignId, quiet: quiet);
  }

  /// Mirrors backend webhook handler: AiCallOutput → normalised entities.
  Call _ingestWebhook(
    Lead lead,
    AiCallOutput out, {
    required String callId,
    required String interactionId,
    required DateTime start,
    String? campaignId,
    bool quiet = false,
  }) {
    final transcript = brain.transcript(lead: lead, out: out, business: business, agent: agent);
    final duration = Duration(seconds: (transcript.lines.lastOrNull?.offset?.inSeconds ?? 60) + 8);
    final score = LeadScore(
      value: out.leadScore,
      temperature: out.temperature,
      intent: out.intent,
      positiveSignals: out.positiveSignals,
      concerns: out.objections,
    );

    String? followUpId;
    if (out.whatsappFollowupRequired && out.whatsappMessage != null) {
      followUpId = _nextId('fu');
      followUps[followUpId] = FollowUp(
        id: followUpId,
        leadId: lead.id,
        leadName: lead.name,
        leadPhone: lead.phone,
        callId: callId,
        message: out.whatsappMessage!,
        status: FollowUpStatus.ready,
        callSummary: out.summary,
        scoreValue: out.leadScore,
        createdAt: start.add(duration),
      );
    }

    if (out.callbackAt != null) {
      callbacks.removeWhere((_, c) => c.leadId == lead.id && c.status == CallbackStatus.scheduled);
      final cbId = _nextId('cb');
      callbacks[cbId] = Callback(
        id: cbId,
        leadId: lead.id,
        leadName: lead.name,
        scheduledAt: out.callbackAt!,
        note: out.temperature == LeadTemperature.hot ? 'Counsellor callback – parents available' : 'Follow-up call',
      );
    }

    final call = Call(
      id: callId,
      leadId: lead.id,
      leadName: lead.name,
      leadPhone: lead.phone,
      campaignId: campaignId,
      agentId: agent.id,
      status: CallStatus.completed,
      duration: duration,
      startedAt: start,
      endedAt: start.add(duration),
      transcript: transcript,
      summary: out.summary,
      outcome: brain.outcomeText(out),
      leadScore: score,
      nextAction: out.nextAction,
      callbackAt: out.callbackAt,
      courseInterest: [out.courseInterest, out.preferredBatch].whereType<String>().join(' · '),
      objections: out.objections,
      followUpId: followUpId,
      interactionId: interactionId,
      rawMetadata: {'connectivity_status': 'connected', 'agent_outputs': out.toJson(), 'provider': 'mock'},
    );
    calls.insert(0, call);

    leads[lead.id] = lead.copyWith(
      status: out.callbackAt != null
          ? LeadStatus.callback
          : out.intent == LeadIntent.notInterested
          ? LeadStatus.notInterested
          : LeadStatus.called,
      score: score,
      summary: out.summary,
      objections: out.objections,
      nextAction: out.nextAction,
      callbackAt: out.callbackAt,
      courseInterest: out.courseInterest,
      preferredBatch: out.preferredBatch,
      budget: out.budget,
      language: out.language,
      lastCallId: callId,
      updatedAt: start.add(duration),
    );

    if (!quiet) {
      usage = usage.copyWith(minutesUsed: usage.minutesUsed + (duration.inSeconds / 60).ceil(), callsMade: usage.callsMade + 1);
      agent = agent.copyWith(callsToday: agent.callsToday + 1);
    }
    return call;
  }

  FollowUp? followUpForLead(String leadId) {
    final l = followUps.values.where((f) => f.leadId == leadId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l.firstOrNull;
  }

  void _emitCallCompleted(Call call, {bool notifyHot = true}) {
    final fu = call.followUpId == null ? null : followUps[call.followUpId];
    _events.add(CallCompletedEvent(call, fu));
    if (call.isHot && notifyHot) {
      final n = AppNotification(
        id: _nextId('n'),
        type: NotificationType.hotLead,
        title: '🔥 Hot lead detected',
        body: '${agent.name} completed a call with ${call.leadName.split(' ').first}. Lead score: ${call.leadScore?.value}.',
        route: fu != null ? '/followups/${fu.id}' : '/calls/${call.id}/result',
        actionLabel: 'Review Follow-up',
        createdAt: DateTime.now(),
      );
      notifications.insert(0, n);
      _events.add(NotificationEvent(n));
    }
    _events.add(const DataChangedEvent('all'));
  }

  // -------------------------------------------------------------- campaigns

  Campaign createCampaign(CampaignDraft d) {
    final c = Campaign(
      id: _nextId('cmp'),
      agentId: agent.id,
      purpose: d.purpose,
      status: CampaignStatus.draft,
      leadIds: d.leadIds,
      languageMode: d.languageMode,
      callingHoursStart: d.callingHoursStart,
      callingHoursEnd: d.callingHoursEnd,
      options: d.options,
      stats: CampaignStats(total: d.leadIds.length, queued: d.leadIds.length),
      estimatedCostInr: estimateCost(d.leadIds.length),
      createdAt: DateTime.now(),
    );
    campaigns[c.id] = c;
    return c;
  }

  int estimateCost(int n) => (n * 0.68 * coachingWorkflowTemplate.estimatedMinutesPerCall * usage.ratePerMinuteInr).round();

  Campaign startCampaign(String id) {
    var c = campaigns[id]!;
    c = c.copyWith(status: CampaignStatus.running, startedAt: DateTime.now());
    campaigns[id] = c;
    for (final lid in c.leadIds) {
      final l = leads[lid];
      if (l != null) leads[lid] = l.copyWith(status: LeadStatus.queued);
    }
    _events.add(CampaignProgressEvent(c));
    _events.add(const DataChangedEvent('leads'));

    var cursor = 0;
    var firstConnectedDone = false;
    String? liveLeadId;
    _campaignTimer?.cancel();
    _campaignTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      var cur = campaigns[id]!;
      if (cur.status != CampaignStatus.running) {
        timer.cancel();
        return;
      }
      // Finish the call that is "live".
      if (liveLeadId != null) {
        final lead = leads[liveLeadId]!;
        final connected = !firstConnectedDone || _rnd.nextDouble() < 0.68;
        LeadTemperature? t;
        if (connected) {
          if (!firstConnectedDone) {
            t = LeadTemperature.hot; // make the demo moment land
          } else {
            final r = _rnd.nextDouble();
            t = r < 0.24 ? LeadTemperature.hot : (r < 0.6 ? LeadTemperature.warm : LeadTemperature.cold);
          }
          firstConnectedDone = true;
        }
        final call = _runCall(
          lead,
          temperature: t,
          connected: connected,
          campaignId: id,
          at: DateTime.now().subtract(const Duration(minutes: 2)),
        );
        final s = cur.stats;
        final interested = call.leadScore != null && call.leadScore!.temperature != LeadTemperature.cold;
        cur = cur.copyWith(
          stats: CampaignStats(
            total: s.total,
            queued: max(0, s.queued - 1),
            completed: s.completed + 1,
            connected: s.connected + (call.status.isConnected ? 1 : 0),
            interested: s.interested + (interested ? 1 : 0),
            hot: s.hot + (call.isHot ? 1 : 0),
          ),
          recentCallIds: [call.id, ...cur.recentCallIds].take(6).toList(),
        );
        campaigns[id] = cur;
        _emitCallCompleted(call, notifyHot: cur.options.notifyHot);
        liveLeadId = null;
      }
      if (cursor >= cur.leadIds.length) {
        timer.cancel();
        cur = cur.copyWith(status: CampaignStatus.completed);
        campaigns[id] = cur;
        final ready = followUps.values.where((f) => f.isPending).length;
        final n = AppNotification(
          id: _nextId('n'),
          type: NotificationType.campaign,
          title: '✅ ${agent.name} finished calling',
          body: '${cur.stats.completed} calls · ${cur.stats.hot} hot leads · $ready follow-ups ready.',
          route: '/followups',
          actionLabel: 'Review & send',
          createdAt: DateTime.now(),
        );
        notifications.insert(0, n);
        activity.insert(
          0,
          ActivityItem(
            emoji: '🚀',
            text: 'Campaign finished: ${cur.stats.completed} calls, ${cur.stats.hot} hot',
            at: DateTime.now(),
            route: '/campaigns/$id',
          ),
        );
        _events.add(NotificationEvent(n));
        _events.add(CampaignProgressEvent(cur));
        return;
      }
      // Dial the next lead.
      liveLeadId = cur.leadIds[cursor++];
      final l = leads[liveLeadId]!;
      leads[liveLeadId!] = l.copyWith(status: LeadStatus.calling);
      _events.add(CampaignProgressEvent(cur));
    });
    return c;
  }

  Campaign stopCampaign(String id) {
    _campaignTimer?.cancel();
    var c = campaigns[id]!;
    c = c.copyWith(status: CampaignStatus.stopped);
    campaigns[id] = c;
    for (final lid in c.leadIds) {
      final l = leads[lid];
      if (l != null && (l.status == LeadStatus.queued || l.status == LeadStatus.calling)) {
        leads[lid] = l.copyWith(status: LeadStatus.newLead);
      }
    }
    _events.add(CampaignProgressEvent(c));
    _events.add(const DataChangedEvent('leads'));
    return c;
  }

  // ------------------------------------------------------------- demo hooks

  /// Simulate one completed call for a new (or freshly created) lead.
  Call simulateCall(LeadTemperature t, {String? leadId}) {
    Lead lead;
    if (leadId != null && leads[leadId] != null) {
      lead = leads[leadId]!;
    } else {
      final fresh = leads.values.where((l) => l.status == LeadStatus.newLead).toList();
      lead = fresh.isNotEmpty
          ? fresh.first
          : _makeLead(_randomName(), _randomPhone(), brain.pick(mockCourses).name, null, DateTime.now(), source: 'Website form');
      leads[lead.id] = lead;
    }
    final call = _runCall(lead, temperature: t, connected: true, at: DateTime.now().subtract(const Duration(minutes: 2)));
    _emitCallCompleted(call);
    return call;
  }

  AppNotification simulateNotification(NotificationType type) {
    final hotFu = followUps.values.where((f) => f.isPending).toList()..sort((a, b) => (b.scoreValue ?? 0).compareTo(a.scoreValue ?? 0));
    final fu = hotFu.firstOrNull;
    final cb = callbacks.values.where((c) => c.status == CallbackStatus.scheduled).firstOrNull;
    final first = (fu?.leadName ?? 'Rahul').split(' ').first;
    final n = switch (type) {
      NotificationType.hotLead => AppNotification(
        id: _nextId('n'),
        type: type,
        title: '🔥 Hot lead detected',
        body: '${agent.name} completed a call with $first. Lead score: ${fu?.scoreValue ?? 87}.',
        route: fu == null ? '/leads?filter=hot' : '/followups/${fu.id}',
        actionLabel: 'Review Follow-up',
        createdAt: DateTime.now(),
      ),
      NotificationType.followUpReady => AppNotification(
        id: _nextId('n'),
        type: type,
        title: '💬 Follow-up ready',
        body: 'Your AI employee prepared a WhatsApp message for $first.',
        route: fu == null ? '/followups' : '/followups/${fu.id}',
        createdAt: DateTime.now(),
      ),
      NotificationType.callback => AppNotification(
        id: _nextId('n'),
        type: type,
        title: '📅 Callback',
        body: '${(cb?.leadName ?? 'Rahul').split(' ').first} asked to speak tomorrow at 6 PM.',
        route: cb == null ? '/callbacks' : '/leads/${cb.leadId}',
        actionLabel: 'View lead',
        createdAt: DateTime.now(),
      ),
      NotificationType.campaign => AppNotification(
        id: _nextId('n'),
        type: type,
        title: '✅ ${agent.name} finished calling',
        body: 'All new leads were called. Follow-ups are ready.',
        route: '/followups',
        createdAt: DateTime.now(),
      ),
    };
    notifications.insert(0, n);
    _events.add(NotificationEvent(n));
    return n;
  }

  void emitChanged(String scope) => _events.add(DataChangedEvent(scope));

  void dispose() {
    _campaignTimer?.cancel();
    _events.close();
  }
}

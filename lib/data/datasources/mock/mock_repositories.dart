import 'dart:async';
import '../../../core/network/api_client.dart' show ApiException;

import '../../../core/utils/phone.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../templates/templates.dart';
import 'mock_backend.dart';

/// Simulated network latency so loading states are real in demo mode.
Future<T> _lag<T>(T Function() f, [int ms = 280]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  return f();
}

Page<T> _page<T>(List<T> all, String? cursor, int limit) {
  final start = int.tryParse(cursor ?? '0') ?? 0;
  final end = (start + limit).clamp(0, all.length);
  return Page(
    items: all.sublist(start.clamp(0, all.length), end),
    hasMore: end < all.length,
    nextCursor: '$end',
  );
}

class MockAuthRepository implements AuthRepository {
  bool _session = true;
  @override
  Future<bool> hasSession() async => _session;
  @override
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
  }) => _lag(() {
    _session = true;
    return GoogleSignInOutcome.signedIn;
  });
  @override
  Future<void> requestOtp({required String phone}) => _lag(() {});
  @override
  Future<void> login({required String phone, required String otp}) =>
      _lag(() => _session = true);
  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
  }) => _lag(() => _session = true);
  @override
  Future<void> logout() async => _session = false;
  @override
  Future<void> deleteAccount() async => _session = false;
}

class MockBusinessRepository implements BusinessRepository {
  MockBusinessRepository(this.b);
  final MockBackend b;
  @override
  Future<Business?> getBusiness() => _lag(() => b.business, 150);
  @override
  Future<Business> saveBusiness(Business business) => _lag(() {
    b.business = business;
    b.emitChanged('business');
    return business;
  });
  @override
  Future<Agent?> getAgent() => _lag(() => b.agent, 150);
  @override
  Future<Agent> saveAgent(Agent agent) => _lag(() {
    b.agent = agent;
    b.emitChanged('agent');
    return agent;
  });
}

class MockKnowledgeRepository implements KnowledgeRepository {
  MockKnowledgeRepository(this.b);
  final MockBackend b;

  @override
  Future<List<KnowledgeSource>> list() => _lag(() => List.of(b.knowledge));

  @override
  Future<KnowledgeSource> get(String id) => _lag(() {
    return b.knowledge.firstWhere(
      (k) => k.id == id,
      orElse: () => throw StateError('Knowledge source not found.'),
    );
  });

  @override
  Stream<KnowledgeSource> add(KnowledgeInput input) async* {
    final detail = switch (input.type) {
      KnowledgeType.pdf => input.fileName ?? 'document.pdf',
      KnowledgeType.website => input.url,
      KnowledgeType.faq =>
        '${(input.content ?? '').split('\n').where((l) => l.trim().endsWith('?')).length.clamp(1, 99)} questions',
      _ => '${(input.content ?? '').split(RegExp(r'\s+')).length} words',
    };
    var src = KnowledgeSource(
      id: 'kn_${DateTime.now().microsecondsSinceEpoch}',
      type: input.type,
      title: input.title,
      detail: detail,
      status: input.type == KnowledgeType.pdf
          ? KnowledgeStatus.uploading
          : KnowledgeStatus.processing,
      progress: 0,
      updatedAt: DateTime.now(),
    );
    yield src;
    if (input.type == KnowledgeType.pdf) {
      for (var p = 0.15; p < 1; p += 0.17) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        yield src = src.copyWith(progress: p);
      }
    }
    if (input.type == KnowledgeType.website &&
        !(input.url ?? '').contains('.')) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      yield src.copyWith(status: KnowledgeStatus.failed);
      return;
    }
    yield src = src.copyWith(status: KnowledgeStatus.processing, progress: 1);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    src = src.copyWith(status: KnowledgeStatus.ready);
    b.knowledge.insert(0, src);
    b.emitChanged('knowledge');
    yield src;
  }

  @override
  Future<void> remove(String id) => _lag(() {
    b.knowledge.removeWhere((k) => k.id == id);
    b.emitChanged('knowledge');
  });
}

int _rank(Lead l) => switch (l.temperature) {
  LeadTemperature.hot => 0,
  LeadTemperature.warm => 1,
  LeadTemperature.unknown =>
    l.status == LeadStatus.calling || l.status == LeadStatus.queued ? 2 : 3,
  LeadTemperature.cold => 4,
};

int leadPriority(Lead a, Lead b) {
  final r = _rank(a).compareTo(_rank(b));
  if (r != 0) return r;
  final s = (b.score?.value ?? 0).compareTo(a.score?.value ?? 0);
  if (s != 0) return s;
  return b.updatedAt.compareTo(a.updatedAt);
}

bool matchesLeadFilter(Lead l, LeadFilter f) => switch (f) {
  LeadFilter.all => true,
  LeadFilter.newLeads =>
    l.status == LeadStatus.newLead ||
        l.status == LeadStatus.queued ||
        l.status == LeadStatus.calling,
  LeadFilter.called => l.hasBeenCalled,
  LeadFilter.hot => l.isHot,
  LeadFilter.warm => l.isWarm,
  LeadFilter.callback =>
    l.status == LeadStatus.callback || l.callbackAt != null,
};

class MockLeadRepository implements LeadRepository {
  MockLeadRepository(this.b);
  final MockBackend b;

  @override
  Future<Page<Lead>> list({
    String? query,
    LeadFilter filter = LeadFilter.all,
    String? cursor,
    int limit = 20,
  }) => _lag(() {
    final q = query?.trim().toLowerCase() ?? '';
    final all =
        b.leads.values
            .where((l) => matchesLeadFilter(l, filter))
            .where(
              (l) =>
                  q.isEmpty ||
                  l.name.toLowerCase().contains(q) ||
                  l.phone.contains(
                    q.replaceAll(RegExp(r'\D'), '').isEmpty
                        ? '\u0000'
                        : q.replaceAll(RegExp(r'\D'), ''),
                  ) ||
                  (l.interest ?? '').toLowerCase().contains(q),
            )
            .toList()
          ..sort(leadPriority);
    return _page(all, cursor, limit);
  });

  @override
  Future<Lead> get(String id) => _lag(() {
    final l = b.leads[id];
    if (l == null) throw StateError('Lead not found');
    return l;
  }, 180);

  @override
  Future<Lead> create(NewLeadInput input) => _lag(() {
    final phone = PhoneUtils.normalize(input.phone);
    if (phone == null) throw ArgumentError('Invalid phone number');
    final now = DateTime.now();
    final l = Lead(
      id: 'lead_${now.microsecondsSinceEpoch}',
      businessId: b.business.id,
      name: input.name,
      phone: phone,
      source: input.source,
      interest: input.interest,
      attributes: input.attributes,
      status: LeadStatus.newLead,
      createdAt: now,
      updatedAt: now,
    );
    b.leads[l.id] = l;
    b.emitChanged('leads');
    return l;
  });

  @override
  Future<LeadImportResult> import(List<NewLeadInput> input) => _lag(() {
    final existing = b.leads.values.map((l) => l.phone).toSet();
    var imported = 0, skipped = 0;
    final now = DateTime.now();
    for (final i in input) {
      final phone = PhoneUtils.normalize(i.phone);
      if (phone == null || !existing.add(phone)) {
        skipped++;
        continue;
      }
      final l = Lead(
        id: 'lead_${now.microsecondsSinceEpoch}_$imported',
        businessId: b.business.id,
        name: i.name,
        phone: phone,
        source: i.source,
        interest: i.interest,
        attributes: i.attributes,
        status: LeadStatus.newLead,
        createdAt: now,
        updatedAt: now,
      );
      b.leads[l.id] = l;
      imported++;
    }
    b.emitChanged('leads');
    return LeadImportResult(imported: imported, skipped: skipped);
  }, 700);

  @override
  Future<Lead> update(Lead lead) => _lag(() {
    b.leads[lead.id] = lead;
    b.emitChanged('leads');
    return lead;
  }, 150);

  @override
  Future<List<Lead>> newLeads() => _lag(
    () => b.leads.values.where((l) => l.status == LeadStatus.newLead).toList(),
    150,
  );
}

class MockCallRepository implements CallRepository {
  MockCallRepository(this.b);
  final MockBackend b;

  @override
  Future<Page<Call>> list({
    CallFilter filter = CallFilter.all,
    String? cursor,
    int limit = 20,
  }) => _lag(() {
    final all =
        b.calls
            .where(
              (c) => switch (filter) {
                CallFilter.all => true,
                CallFilter.connected => c.status.isConnected,
                CallFilter.noAnswer =>
                  c.status == CallStatus.noAnswer ||
                      c.status == CallStatus.busy,
                CallFilter.hot => c.isHot,
              },
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return _page(all, cursor, limit);
  });

  @override
  Future<Call> get(String id) => _lag(
    () => b.calls.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('Call not found'),
    ),
    180,
  );

  @override
  Future<List<Call>> forLead(String leadId) => _lag(
    () =>
        b.calls.where((c) => c.leadId == leadId).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
    150,
  );

  @override
  Future<Call> triggerCall(String leadId) => _lag(() {
    return b.simulateCall(LeadTemperature.hot, leadId: leadId);
  }, 300);
}

class MockCampaignRepository implements CampaignRepository {
  MockCampaignRepository(this.b);
  final MockBackend b;

  @override
  Future<Campaign> create(CampaignDraft draft) =>
      _lag(() => b.createCampaign(draft));
  @override
  Future<Campaign> get(String id) => _lag(
    () => b.campaigns[id] ?? (throw StateError('Campaign not found')),
    120,
  );
  @override
  Future<Campaign> start(String id, {bool consentAttestation = false}) =>
      _lag(() => b.startCampaign(id), 500);
  @override
  Future<Campaign> stop(String id) => _lag(() => b.stopCampaign(id));
  @override
  Future<Campaign?> active() =>
      _lag(() => b.campaigns.values.where((c) => c.isActive).firstOrNull, 100);
  @override
  int estimateCostInr(int leadCount) => b.estimateCost(leadCount);
}

class MockFollowUpRepository implements FollowUpRepository {
  MockFollowUpRepository(this.b);
  final MockBackend b;

  @override
  Future<List<FollowUp>> list({bool pendingOnly = false}) => _lag(() {
    final l =
        b.followUps.values.where((f) => !pendingOnly || f.isPending).toList()
          ..sort((a, b) {
            if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
            final s = (b.scoreValue ?? 0).compareTo(a.scoreValue ?? 0);
            return s != 0 ? s : b.createdAt.compareTo(a.createdAt);
          });
    return l;
  });

  @override
  Future<FollowUp> get(String id) => _lag(
    () => b.followUps[id] ?? (throw StateError('Follow-up not found')),
    150,
  );

  @override
  Future<FollowUp> update(FollowUp f) => _lag(() {
    b.followUps[f.id] = f;
    b.emitChanged('followups');
    return f;
  }, 120);

  @override
  Future<FollowUp?> forCall(String callId) => _lag(
    () => b.followUps.values.where((f) => f.callId == callId).firstOrNull,
    100,
  );
}

class MockCallbackRepository implements CallbackRepository {
  MockCallbackRepository(this.b);
  final MockBackend b;

  @override
  Future<List<Callback>> list() => _lag(
    () =>
        b.callbacks.values.toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)),
  );

  @override
  Future<Callback> schedule({
    required String leadId,
    required DateTime at,
    String? note,
  }) => _lag(() {
    final lead = b.leads[leadId];
    if (lead == null) throw StateError('Lead not found');
    b.callbacks.removeWhere(
      (_, c) => c.leadId == leadId && c.status == CallbackStatus.scheduled,
    );
    final cb = Callback(
      id: 'cb_${DateTime.now().microsecondsSinceEpoch}',
      leadId: leadId,
      leadName: lead.name,
      scheduledAt: at,
      note:
          note ??
          '${templateFor(b.business.category).workflow.humanLabel} follow-up',
    );
    b.callbacks[cb.id] = cb;
    b.leads[leadId] = lead.copyWith(
      callbackAt: at,
      status: LeadStatus.callback,
    );
    b.emitChanged('callbacks');
    return cb;
  });

  @override
  Future<Callback> markDone(String id) => _lag(() {
    final cb = b.callbacks[id]!.copyWith(status: CallbackStatus.done);
    b.callbacks[id] = cb;
    final lead = b.leads[cb.leadId];
    if (lead != null) {
      b.leads[cb.leadId] = lead.copyWith(
        clearCallback: true,
        status: LeadStatus.called,
      );
    }
    b.emitChanged('callbacks');
    return cb;
  });
}

class MockUsageRepository implements UsageRepository {
  MockUsageRepository(this.b);
  final MockBackend b;
  @override
  Future<Usage> get() => _lag(() => b.usage);
  @override
  Future<String?> checkout({String planId = 'starter'}) => _lag(() {
    if (!b.simulatePlanPayment(planId: planId)) {
      throw const ApiException(
        'Extra minutes can be added to an active plan. Buy or renew a plan first.',
        statusCode: 409,
        code: 'plan_not_active',
      );
    }
    return null;
  });
}

class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository(this.b);
  final MockBackend b;
  @override
  Future<List<AppNotification>> list() =>
      _lag(() => List.of(b.notifications), 150);
  @override
  Future<void> markRead(String id) async {
    final i = b.notifications.indexWhere((n) => n.id == id);
    if (i >= 0) b.notifications[i] = b.notifications[i].copyWith(read: true);
  }
}

class MockDashboardRepository implements DashboardRepository {
  MockDashboardRepository(this.b);
  final MockBackend b;

  @override
  Future<DailySummary> today() => _lag(() {
    final now = DateTime.now();
    final todayCalls = b.calls.where(
      (c) =>
          c.startedAt.year == now.year &&
          c.startedAt.day == now.day &&
          c.startedAt.month == now.month,
    );
    final calledLeadIds = todayCalls.map((c) => c.leadId).toSet();
    final connected = todayCalls
        .where((c) => c.status.isConnected)
        .map((c) => c.leadId)
        .toSet();
    final interested = b.leads.values
        .where((l) => connected.contains(l.id) && (l.isHot || l.isWarm))
        .length;
    final hot = b.leads.values.where((l) => l.isHot).length;
    final cbToday = b.callbacks.values
        .where((c) => c.status == CallbackStatus.scheduled)
        .length;
    return DailySummary(
      leads: b.leads.length,
      connected: connected.length,
      interested: interested,
      hot: hot,
      callsToday: calledLeadIds.isEmpty ? 0 : todayCalls.length,
      followUpsReady: b.followUps.values.where((f) => f.isPending).length,
      callbacksToday: cbToday,
      newLeadsReady: b.leads.values
          .where((l) => l.status == LeadStatus.newLead)
          .length,
      activity: List.of(b.activity.take(5)),
    );
  });
}

class MockVoiceSessionRepository implements VoiceSessionRepository {
  @override
  Future<VoiceTestSession> createTestSession() => _lag(
    () => const VoiceTestSession(
      sessionToken: 'demo',
      orgId: 'demo',
      workspaceId: 'demo',
      appId: 'demo',
      proxyBaseUrl: '',
    ),
    400,
  );

  @override
  Future<void> endTestSession(String sessionId) async {}

  @override
  Future<VoiceChatReply> sendChatMessage(
    String message, {
    String? conversationId,
  }) => _lag(
    () => VoiceChatReply(
      reply:
          'I am here to help you answer questions and schedule follow-ups for your business.',
      conversationId: conversationId ?? 'conv_mock_123',
    ),
    400,
  );
}

class MockDeviceRepository implements DeviceRepository {
  @override
  Future<void> registerDevice({
    required String token,
    String? platform,
  }) async {}

  @override
  Future<void> unregisterDevice(String token) async {}
}

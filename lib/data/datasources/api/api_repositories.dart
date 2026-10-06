import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_store.dart';
import '../../models/models.dart';
import '../../repositories/repositories.dart';

/// Production repositories talking to OUR backend (contract: backend/API.md).
/// The backend owns Sarvam, telephony, webhooks and secrets.

Json _j(dynamic d) => Map<String, dynamic>.from(d as Map);
List<Json> _l(dynamic d) {
  final list = d is Map ? (d['items'] ?? d['data'] ?? const []) : d;
  return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Page<T> _p<T>(dynamic d, T Function(Json) f) {
  final m = _j(d);
  return Page(items: _l(m).map(f).toList(), hasMore: m['has_more'] == true, nextCursor: m['next_cursor']?.toString());
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this.api, this.store);
  final ApiClient api;
  final SecureStore store;

  @override
  Future<bool> hasSession() async => (await store.accessToken()) != null;

  Future<void> _save(dynamic d) async {
    final m = _j(d);
    await store.saveTokens(access: m['access_token'] as String, refresh: m['refresh_token'] as String?);
  }

  @override
  Future<void> login({required String phone, required String otp}) =>
      api.post('/auth/login', (d) => _save(d), data: {'phone': phone, 'otp': otp});

  @override
  Future<void> register({required String phone, required String businessName}) =>
      api.post('/auth/register', (d) => _save(d), data: {'phone': phone, 'business_name': businessName});

  @override
  Future<void> logout() => store.clear();

  @override
  Future<void> deleteAccount() async {
    await api.delete('/auth/account');
    await store.clear();
  }
}

class ApiBusinessRepository implements BusinessRepository {
  ApiBusinessRepository(this.api);
  final ApiClient api;
  @override
  Future<Business?> getBusiness() => api.get('/business', (d) => d == null ? null : Business.fromJson(_j(d)));
  @override
  Future<Business> saveBusiness(Business b) => api.patch('/business', (d) => Business.fromJson(_j(d)), data: b.toJson());
  @override
  Future<Agent?> getAgent() => api.get('/agent', (d) => d == null ? null : Agent.fromJson(_j(d)));
  @override
  Future<Agent> saveAgent(Agent a) => api.patch('/agent', (d) => Agent.fromJson(_j(d)), data: a.toJson());
}

class ApiKnowledgeRepository implements KnowledgeRepository {
  ApiKnowledgeRepository(this.api);
  final ApiClient api;

  @override
  Future<List<KnowledgeSource>> list() => api.get('/knowledge', (d) => _l(d).map(KnowledgeSource.fromJson).toList());

  @override
  Stream<KnowledgeSource> add(KnowledgeInput input) {
    final c = StreamController<KnowledgeSource>();
    () async {
      try {
        final pending = KnowledgeSource(
          id: 'pending',
          type: input.type,
          title: input.title,
          detail: input.fileName ?? input.url,
          status: KnowledgeStatus.uploading,
          progress: 0,
          updatedAt: DateTime.now(),
        );
        c.add(pending);
        final form = FormData.fromMap({
          'type': input.type.wire,
          'title': input.title,
          if (input.content != null) 'content': input.content,
          if (input.url != null) 'url': input.url,
          if (input.bytes != null) 'file': MultipartFile.fromBytes(input.bytes!, filename: input.fileName ?? 'upload.pdf'),
        });
        final res = await api.dio.post(
          '/knowledge',
          data: form,
          onSendProgress: (s, t) {
            if (t > 0) c.add(pending.copyWith(progress: s / t));
          },
        );
        var src = KnowledgeSource.fromJson(_j(res.data));
        c.add(src);
        // Poll until processed (backend extracts text & syncs to the agent KB).
        for (var i = 0; i < 30 && src.status == KnowledgeStatus.processing; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          src = await api.get('/knowledge/${src.id}', (d) => KnowledgeSource.fromJson(_j(d)));
          c.add(src);
        }
      } on DioException catch (_) {
        c.addError(const ApiException('Upload failed. Try again.'));
      } catch (e) {
        c.addError(e);
      } finally {
        await c.close();
      }
    }();
    return c.stream;
  }

  @override
  Future<void> remove(String id) => api.delete('/knowledge/$id');
}

class ApiLeadRepository implements LeadRepository {
  ApiLeadRepository(this.api);
  final ApiClient api;

  static String _f(LeadFilter f) => switch (f) {
    LeadFilter.all => 'all',
    LeadFilter.newLeads => 'new',
    LeadFilter.called => 'called',
    LeadFilter.hot => 'hot',
    LeadFilter.warm => 'warm',
    LeadFilter.callback => 'callback',
  };

  @override
  Future<Page<Lead>> list({String? query, LeadFilter filter = LeadFilter.all, String? cursor, int limit = 20}) =>
      api.get('/leads', (d) => _p(d, Lead.fromJson), query: {'q': ?query, 'filter': _f(filter), 'cursor': ?cursor, 'limit': limit});

  @override
  Future<Lead> get(String id) => api.get('/leads/$id', (d) => Lead.fromJson(_j(d)));

  @override
  Future<Lead> create(NewLeadInput input) => api.post('/leads', (d) => Lead.fromJson(_j(d)), data: input.toJson());

  @override
  Future<LeadImportResult> import(List<NewLeadInput> leads) =>
      api.post('/leads/import', (d) => LeadImportResult.fromJson(_j(d)), data: {'leads': leads.map((e) => e.toJson()).toList()});

  @override
  Future<Lead> update(Lead lead) => api.patch('/leads/${lead.id}', (d) => Lead.fromJson(_j(d)), data: lead.toJson());

  @override
  Future<List<Lead>> newLeads() =>
      api.get('/leads', (d) => _l(d).map(Lead.fromJson).toList(), query: {'filter': 'new', 'limit': 1000, 'fields': 'id,name,phone'});
}

class ApiCallRepository implements CallRepository {
  ApiCallRepository(this.api);
  final ApiClient api;

  @override
  Future<Page<Call>> list({CallFilter filter = CallFilter.all, String? cursor, int limit = 20}) =>
      api.get('/calls', (d) => _p(d, Call.fromJson), query: {'filter': filter.name, 'cursor': ?cursor, 'limit': limit});

  @override
  Future<Call> get(String id) => api.get('/calls/$id', (d) => Call.fromJson(_j(d)));

  @override
  Future<List<Call>> forLead(String leadId) => api.get('/calls', (d) => _l(d).map(Call.fromJson).toList(), query: {'lead_id': leadId});

  @override
  Future<Call> triggerCall(String leadId) =>
      api.post('/leads/$leadId/call', (d) => Call.fromJson(_j(d is Map && d.containsKey('call') ? d['call'] : d)));
}

class ApiCampaignRepository implements CampaignRepository {
  ApiCampaignRepository(this.api);
  final ApiClient api;
  @override
  Future<Campaign> create(CampaignDraft draft) => api.post('/campaigns', (d) => Campaign.fromJson(_j(d)), data: draft.toJson());
  @override
  Future<Campaign> get(String id) => api.get('/campaigns/$id', (d) => Campaign.fromJson(_j(d)));
  @override
  Future<Campaign> start(String id) => api.post('/campaigns/$id/start', (d) => Campaign.fromJson(_j(d)));
  @override
  Future<Campaign> stop(String id) => api.post('/campaigns/$id/stop', (d) => Campaign.fromJson(_j(d)));
  @override
  Future<Campaign?> active() => api.get('/campaigns', (d) {
    final l = _l(d).map(Campaign.fromJson).where((c) => c.isActive);
    return l.isEmpty ? null : l.first;
  }, query: {'status': 'running'});
  @override
  int estimateCostInr(int leadCount) => (leadCount * 0.68 * 2.2 * 6).round();
}

class ApiFollowUpRepository implements FollowUpRepository {
  ApiFollowUpRepository(this.api);
  final ApiClient api;
  @override
  Future<List<FollowUp>> list({bool pendingOnly = false}) =>
      api.get('/followups', (d) => _l(d).map(FollowUp.fromJson).toList(), query: {if (pendingOnly) 'status': 'ready'});
  @override
  Future<FollowUp> get(String id) => api.get('/followups/$id', (d) => FollowUp.fromJson(_j(d)));
  @override
  Future<FollowUp> update(FollowUp f) => api.patch(
    '/followups/${f.id}',
    (d) => FollowUp.fromJson(_j(d)),
    data: {'message': f.message, 'status': f.status.wire, 'opened_at': dateOut(f.openedAt)},
  );
  @override
  Future<FollowUp?> forCall(String callId) => api.get('/followups', (d) {
    final l = _l(d);
    return l.isEmpty ? null : FollowUp.fromJson(l.first);
  }, query: {'call_id': callId});
}

class ApiCallbackRepository implements CallbackRepository {
  ApiCallbackRepository(this.api);
  final ApiClient api;
  @override
  Future<List<Callback>> list() => api.get('/callbacks', (d) => _l(d).map(Callback.fromJson).toList());
  @override
  Future<Callback> schedule({required String leadId, required DateTime at, String? note}) =>
      api.post('/callbacks', (d) => Callback.fromJson(_j(d)), data: {'lead_id': leadId, 'scheduled_at': dateOut(at), 'note': note});
  @override
  Future<Callback> markDone(String id) => api.patch('/callbacks/$id', (d) => Callback.fromJson(_j(d)), data: {'status': 'done'});
}

class ApiUsageRepository implements UsageRepository {
  ApiUsageRepository(this.api);
  final ApiClient api;
  @override
  Future<Usage> get() => api.get('/usage', (d) => Usage.fromJson(_j(d)));
}

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this.api);
  final ApiClient api;
  @override
  Future<List<AppNotification>> list() => api.get('/notifications', (d) => _l(d).map(AppNotification.fromJson).toList());
  @override
  Future<void> markRead(String id) => api.patch('/notifications/$id', (_) {}, data: {'read': true});
}

class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository(this.api);
  final ApiClient api;
  @override
  Future<DailySummary> today() => api.get('/dashboard/today', (d) {
    final m = _j(d);
    return DailySummary(
      leads: jInt(m, 'leads'),
      connected: jInt(m, 'connected'),
      interested: jInt(m, 'interested'),
      hot: jInt(m, 'hot'),
      callsToday: jInt(m, 'calls_today'),
      followUpsReady: jInt(m, 'followups_ready'),
      callbacksToday: jInt(m, 'callbacks_today'),
      newLeadsReady: jInt(m, 'new_leads_ready'),
      activity: jList(
        m,
        'activity',
        (a) => ActivityItem(
          emoji: jStr(a, 'emoji', '•'),
          text: jStr(a, 'text'),
          at: jDate(a, 'at') ?? DateTime.now(),
          route: jStrN(a, 'route'),
        ),
      ),
    );
  });
}

class ApiVoiceSessionRepository implements VoiceSessionRepository {
  ApiVoiceSessionRepository(this.api);
  final ApiClient api;
  @override
  Future<VoiceTestSession> createTestSession() => api.post('/voice/test-session', (d) => VoiceTestSession.fromJson(_j(d)));
}

class ApiDeviceRepository implements DeviceRepository {
  ApiDeviceRepository(this.api);
  final ApiClient api;
  @override
  Future<void> registerDevice({required String token, String? platform}) =>
      api.post('/devices/register', (_) {}, data: {'token': token, if (platform != null) 'platform': platform});
}

/// Production event source. Remote push (FCM data messages) is forwarded here
/// by the notification service; screens simply refresh on DataChangedEvent.
class PushBackendEvents implements BackendEvents {
  final _c = StreamController<BackendEvent>.broadcast();
  @override
  Stream<BackendEvent> get stream => _c.stream;
  void add(BackendEvent e) => _c.add(e);
}

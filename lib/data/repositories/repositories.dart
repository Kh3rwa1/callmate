import '../models/models.dart';

/// Repository interfaces. UI depends only on these.
/// Two implementations exist:
///   * Mock*  – in-memory demo backend with a simulated AI call engine
///   * Api*   – Dio client against our backend (see backend/API.md)

abstract class AuthRepository {
  Future<bool> hasSession();
  Future<void> login({required String phone, required String otp});
  Future<void> register({required String phone, required String businessName});
  Future<void> logout();
}

abstract class BusinessRepository {
  Future<Business?> getBusiness();
  Future<Business> saveBusiness(Business business);
  Future<Agent?> getAgent();
  Future<Agent> saveAgent(Agent agent);
}

abstract class KnowledgeRepository {
  Future<List<KnowledgeSource>> list();

  /// Emits the source while it uploads/processes, ending in ready/failed.
  Stream<KnowledgeSource> add(KnowledgeInput input);
  Future<void> remove(String id);
}

abstract class LeadRepository {
  Future<Page<Lead>> list({String? query, LeadFilter filter = LeadFilter.all, String? cursor, int limit = 20});
  Future<Lead> get(String id);
  Future<Lead> create(NewLeadInput input);
  Future<LeadImportResult> import(List<NewLeadInput> leads);
  Future<Lead> update(Lead lead);
  Future<List<Lead>> newLeads();
}

enum LeadFilter { all, newLeads, called, hot, warm, callback }

abstract class CallRepository {
  Future<Page<Call>> list({CallFilter filter = CallFilter.all, String? cursor, int limit = 20});
  Future<Call> get(String id);
  Future<List<Call>> forLead(String leadId);
}

enum CallFilter { all, connected, noAnswer, hot }

abstract class CampaignRepository {
  Future<Campaign> create(CampaignDraft draft);
  Future<Campaign> get(String id);
  Future<Campaign> start(String id);
  Future<Campaign> stop(String id);
  Future<Campaign?> active();
  int estimateCostInr(int leadCount);
}

abstract class FollowUpRepository {
  Future<List<FollowUp>> list({bool pendingOnly = false});
  Future<FollowUp> get(String id);
  Future<FollowUp> update(FollowUp followUp);
  Future<FollowUp?> forCall(String callId);
}

abstract class CallbackRepository {
  Future<List<Callback>> list();
  Future<Callback> schedule({required String leadId, required DateTime at, String? note});
  Future<Callback> markDone(String id);
}

abstract class UsageRepository {
  Future<Usage> get();
}

abstract class NotificationRepository {
  Future<List<AppNotification>> list();
  Future<void> markRead(String id);
}

abstract class DashboardRepository {
  Future<DailySummary> today();
}

abstract class VoiceSessionRepository {
  /// POST /voice/test-session – backend returns ids + short-lived proxy token.
  Future<VoiceTestSession> createTestSession();
}

/// Realtime-ish backend events (in production: FCM data messages / SSE).
abstract class BackendEvents {
  Stream<BackendEvent> get stream;
}

sealed class BackendEvent {
  const BackendEvent();
}

class CallCompletedEvent extends BackendEvent {
  const CallCompletedEvent(this.call, this.followUp);
  final Call call;
  final FollowUp? followUp;
}

class CampaignProgressEvent extends BackendEvent {
  const CampaignProgressEvent(this.campaign);
  final Campaign campaign;
}

class DataChangedEvent extends BackendEvent {
  const DataChangedEvent(this.scope);
  final String scope; // leads | calls | followups | knowledge | agent | callbacks
}

class NotificationEvent extends BackendEvent {
  const NotificationEvent(this.notification);
  final AppNotification notification;
}

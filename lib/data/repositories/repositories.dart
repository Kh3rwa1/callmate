import '../models/models.dart';

/// Repository interfaces. UI depends only on these.
/// Two implementations exist:
///   * Mock*  – in-memory demo backend with a simulated AI call engine
///   * Api*   – Dio client against our backend (see backend/API.md)

/// Outcome of `POST /auth/google`.
enum GoogleSignInOutcome { signedIn, registrationRequired }

abstract class AuthRepository {
  Future<bool> hasSession();

  /// Exchanges a Firebase ID token for our session. New accounts also need
  /// [businessName] and [phone]; without them the result is
  /// [GoogleSignInOutcome.registrationRequired]. [referralCode] (optional) is
  /// the code of the business that invited this one.
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
    String? referralCode,
  });
  Future<void> requestOtp({required String phone});
  Future<void> login({required String phone, required String otp});
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
    String? referralCode,
  });
  Future<void> logout();
  Future<void> deleteAccount();
}

abstract class BusinessRepository {
  Future<Business?> getBusiness();
  Future<Business> saveBusiness(Business business);
  Future<Agent?> getAgent();
  Future<Agent> saveAgent(Agent agent);
}

abstract class KnowledgeRepository {
  Future<List<KnowledgeSource>> list();
  Future<KnowledgeSource> get(String id);

  /// Emits the source while it uploads/processes, ending in ready/failed.
  Stream<KnowledgeSource> add(KnowledgeInput input);
  Future<void> remove(String id);
}

abstract class LeadRepository {
  Future<Page<Lead>> list({
    String? query,
    LeadFilter filter = LeadFilter.all,
    String? cursor,
    int limit = 20,
  });
  Future<Lead> get(String id);
  Future<Lead> create(NewLeadInput input);
  Future<LeadImportResult> import(List<NewLeadInput> leads);
  Future<Lead> update(Lead lead);
  Future<List<Lead>> newLeads();
}

enum LeadFilter { all, newLeads, called, hot, warm, callback }

abstract class CallRepository {
  Future<Page<Call>> list({
    CallFilter filter = CallFilter.all,
    String? cursor,
    int limit = 20,
  });
  Future<Call> get(String id);
  Future<List<Call>> forLead(String leadId);
  Future<Call> triggerCall(String leadId);
}

enum CallFilter { all, connected, noAnswer, hot }

abstract class CampaignRepository {
  Future<Campaign> create(CampaignDraft draft);
  Future<Campaign> get(String id);
  Future<Campaign> start(String id, {bool consentAttestation = false});
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
  Future<Callback> schedule({
    required String leadId,
    required DateTime at,
    String? note,
  });
  Future<Callback> markDone(String id);
}

abstract class UsageRepository {
  Future<Usage> get();

  /// Starts a payment for [planId]. Returns the payment page URL to open, or
  /// null when no page is needed (the mock backend "pays" instantly).
  /// Throws `ApiException(code: 'billing_not_configured')` when online
  /// payments are not set up.
  Future<String?> checkout({String planId = 'starter'});
}

/// Referral program (`GET /referrals`).
abstract class ReferralRepository {
  Future<ReferralSummary> get();
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

  /// POST /voice/test-session/:id/end – releases the session slot.
  Future<void> endTestSession(String sessionId);
  Future<VoiceChatReply> sendChatMessage(
    String message, {
    String? conversationId,
  });
}

abstract class DeviceRepository {
  Future<void> registerDevice({required String token, String? platform});
  Future<void> unregisterDevice(String token);
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
  final String
  scope; // leads | calls | followups | knowledge | agent | callbacks
}

class NotificationEvent extends BackendEvent {
  const NotificationEvent(this.notification);
  final AppNotification notification;
}

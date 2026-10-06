import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/api/api_repositories.dart';
import '../data/datasources/mock/mock_backend.dart';
import '../data/datasources/mock/mock_repositories.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import '../data/templates/templates.dart';
import '../services/analytics/analytics_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/voice/sarvam_voice_agent_service.dart';
import '../services/voice/voice_agent_service.dart';
import '../services/whatsapp/whatsapp_service.dart';
import 'config/app_env.dart';
import 'config/brand.dart';
import 'network/api_client.dart';
import 'storage/local_prefs.dart';
import 'storage/secure_store.dart';

/// ---------------------------------------------------------------------------
/// Composition root. Flip between mock & production with ONE switch:
/// `AppEnv.useMock` (true when API_BASE_URL is empty or USE_MOCK=true).
/// ---------------------------------------------------------------------------

final useMockProvider = Provider<bool>((_) => AppEnv.useMock);

final localPrefsProvider = Provider<LocalPrefs>((_) => throw UnimplementedError('override in main'));
final secureStoreProvider = Provider<SecureStore>((_) => SecureStore());
final apiClientProvider = Provider<ApiClient>((ref) {
  LocalPrefs? prefs;
  try {
    prefs = ref.watch(localPrefsProvider);
  } catch (_) {}
  return ApiClient(
    ref.watch(secureStoreProvider),
    prefs: prefs,
    onAuthFailure: () {
      ref.read(sessionProvider.notifier).forceLogout();
    },
  );
});

final mockBackendProvider = Provider<MockBackend>((ref) {
  final b = MockBackend();
  ref.onDispose(b.dispose);
  return b;
});

T _pick<T>(Ref ref, T Function(MockBackend) mock, T Function(ApiClient) api) =>
    ref.watch(useMockProvider) ? mock(ref.watch(mockBackendProvider)) : api(ref.watch(apiClientProvider));

final authRepoProvider = Provider<AuthRepository>(
  (ref) =>
      ref.watch(useMockProvider) ? MockAuthRepository() : ApiAuthRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider)),
);

final sessionProvider = AsyncNotifierProvider<SessionNotifier, bool>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.watch(authRepoProvider).hasSession();
  }

  Future<void> requestOtp({required String phone}) async {
    await ref.read(authRepoProvider).requestOtp(phone: phone);
  }

  Future<void> login({required String phone, required String otp}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepoProvider).login(phone: phone, otp: otp);
      ref.read(dataVersionProvider.notifier).bump();
      return true;
    });
  }

  Future<void> register({required String phone, required String businessName, required String otp}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepoProvider).register(phone: phone, businessName: businessName, otp: otp);
      ref.read(dataVersionProvider.notifier).bump();
      return true;
    });
  }

  Future<void> forceLogout() async {
    state = const AsyncValue.data(false);
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepoProvider).logout();
      ref.read(dataVersionProvider.notifier).bump();
      return false;
    });
  }

  Future<void> deleteAccount() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepoProvider).deleteAccount();
      ref.read(dataVersionProvider.notifier).bump();
      return false;
    });
  }
}

final businessRepoProvider = Provider<BusinessRepository>((ref) => _pick(ref, MockBusinessRepository.new, ApiBusinessRepository.new));
final knowledgeRepoProvider = Provider<KnowledgeRepository>((ref) => _pick(ref, MockKnowledgeRepository.new, ApiKnowledgeRepository.new));
final leadRepoProvider = Provider<LeadRepository>((ref) => _pick(ref, MockLeadRepository.new, ApiLeadRepository.new));
final callRepoProvider = Provider<CallRepository>((ref) => _pick(ref, MockCallRepository.new, ApiCallRepository.new));
final campaignRepoProvider = Provider<CampaignRepository>((ref) => _pick(ref, MockCampaignRepository.new, ApiCampaignRepository.new));
final followUpRepoProvider = Provider<FollowUpRepository>((ref) => _pick(ref, MockFollowUpRepository.new, ApiFollowUpRepository.new));
final callbackRepoProvider = Provider<CallbackRepository>((ref) => _pick(ref, MockCallbackRepository.new, ApiCallbackRepository.new));
final usageRepoProvider = Provider<UsageRepository>((ref) => _pick(ref, MockUsageRepository.new, ApiUsageRepository.new));
final notificationRepoProvider = Provider<NotificationRepository>(
  (ref) => _pick(ref, MockNotificationRepository.new, ApiNotificationRepository.new),
);
final dashboardRepoProvider = Provider<DashboardRepository>((ref) => _pick(ref, MockDashboardRepository.new, ApiDashboardRepository.new));
final voiceSessionRepoProvider = Provider<VoiceSessionRepository>(
  (ref) => _pick(ref, (_) => MockVoiceSessionRepository(), ApiVoiceSessionRepository.new),
);
final deviceRepoProvider = Provider<DeviceRepository>(
  (ref) => _pick(ref, (_) => MockDeviceRepository(), ApiDeviceRepository.new),
);

final backendEventsProvider = Provider<BackendEvents>((ref) {
  if (ref.watch(useMockProvider)) return ref.watch(mockBackendProvider);
  return PushBackendEvents();
});

/// Services
final whatsappServiceProvider = Provider<WhatsAppService>((_) => const WhatsAppDeepLinkService());
final analyticsProvider = Provider<AnalyticsService>((_) => DebugAnalyticsService());
final notificationServiceProvider = Provider<NotificationService>((_) => NotificationService());

/// Voice service instance (100% real Sarvam AI voice agent).
final voiceAgentServiceProvider = Provider<VoiceAgentService>((ref) {
  final s = SarvamVoiceAgentService(ref.watch(voiceSessionRepoProvider));
  ref.onDispose(s.dispose);
  return s;
});

/// ---------------------------------------------------------------------------
/// Shared read models. Invalidated whenever the backend reports changes, so
/// every screen stays fresh without polling.
/// ---------------------------------------------------------------------------

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

class DataVersion extends Notifier<int> {
  @override
  int build() {
    final sub = ref.watch(backendEventsProvider).stream.listen((e) {
      if (e is DataChangedEvent || e is CallCompletedEvent) state++;
    });
    ref.onDispose(sub.cancel);
    return 0;
  }

  void bump() => state++;
}

final businessProvider = FutureProvider<Business?>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(businessRepoProvider).getBusiness();
});

final agentProvider = FutureProvider<Agent?>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(businessRepoProvider).getAgent();
});

final dashboardProvider = FutureProvider<DailySummary>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(dashboardRepoProvider).today();
});

final followUpsProvider = FutureProvider<List<FollowUp>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(followUpRepoProvider).list();
});

final followUpProvider = FutureProvider.family<FollowUp, String>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(followUpRepoProvider).get(id);
});

final leadProvider = FutureProvider.family<Lead, String>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(leadRepoProvider).get(id);
});

final leadCallsProvider = FutureProvider.family<List<Call>, String>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(callRepoProvider).forLead(id);
});

final callProvider = FutureProvider.family<Call, String>((ref, id) => ref.watch(callRepoProvider).get(id));

final callbacksProvider = FutureProvider<List<Callback>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(callbackRepoProvider).list();
});

final knowledgeProvider = FutureProvider<List<KnowledgeSource>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(knowledgeRepoProvider).list();
});

final usageProvider = FutureProvider<Usage>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(usageRepoProvider).get();
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(notificationRepoProvider).list();
});

final newLeadsProvider = FutureProvider<List<Lead>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(leadRepoProvider).newLeads();
});

/// Live campaign (if any) – kept in sync from backend progress events.
final activeCampaignProvider = NotifierProvider<ActiveCampaign, Campaign?>(ActiveCampaign.new);

class ActiveCampaign extends Notifier<Campaign?> {
  @override
  Campaign? build() {
    final sub = ref.watch(backendEventsProvider).stream.listen((e) {
      if (e is CampaignProgressEvent) state = e.campaign;
    });
    ref.onDispose(sub.cancel);
    unawaited(
      ref
          .read(campaignRepoProvider)
          .active()
          .then((c) {
            if (c != null) state = c;
          })
          .catchError((_) {}),
    );
    return null;
  }

  void set(Campaign c) => state = c;
}

/// ---------------------------------------------------------------------------
/// Active template context. Every screen pulls vertical vocabulary from here
/// (interest label, human closer, knowledge hints…) so changing
/// business.category / agent.name / agent.role re-skins the whole UI.
/// ---------------------------------------------------------------------------
final businessTemplateProvider = Provider<BusinessTemplate>((ref) {
  final cat = ref.watch(businessProvider).value?.category;
  return templateFor(cat);
});

final workflowProvider = Provider<WorkflowTemplate>((ref) => ref.watch(businessTemplateProvider).workflow);

/// Employee display name – never falls back to a hardcoded persona.
final employeeNameProvider = Provider<String>((ref) => ref.watch(agentProvider).value?.name ?? Brand.employeeFallbackName);

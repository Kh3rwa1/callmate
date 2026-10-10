import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/api/api_repositories.dart';
import '../data/datasources/mock/mock_backend.dart';
import '../data/datasources/mock/mock_repositories.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import '../data/templates/templates.dart';
import '../l10n/l10n.dart';
import '../services/analytics/analytics_service.dart';
import '../services/attribution/install_referrer.dart';
import '../services/auth/google_auth_service.dart';
import '../services/crash/crash_reporting_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/notifications/push_service.dart';
import '../services/voice/sarvam_voice_agent_service.dart';
import '../services/voice/voice_agent_service.dart';
import '../services/whatsapp/whatsapp_service.dart';
import 'config/app_env.dart';
import 'config/brand.dart';
import 'network/api_client.dart';
import 'routing/app_router.dart';
import 'routing/deep_link.dart';
import 'settings.dart';
import 'storage/local_prefs.dart';
import 'storage/secure_store.dart';

/// ---------------------------------------------------------------------------
/// Composition root. Flip between mock & production with ONE switch:
/// `AppEnv.useMock` (true when API_BASE_URL is empty or USE_MOCK=true).
/// ---------------------------------------------------------------------------

final useMockProvider = Provider<bool>((_) => AppEnv.useMock);

final localPrefsProvider = Provider<LocalPrefs>(
  (_) => throw UnimplementedError('override in main'),
);
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
    onMutation: (path) {
      final scope = mutationScope(path);
      final events = ref.read(backendEventsProvider);
      if (scope != null && events is PushBackendEvents) {
        events.add(DataChangedEvent(scope));
      }
    },
  );
});

/// [DataChangedEvent] scope for a successful write to [path], or null when
/// the write changes no data a screen shows (auth, devices, voice sessions).
@visibleForTesting
String? mutationScope(String path) {
  final first = path
      .split('/')
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  return switch (first) {
    'auth' || 'devices' || 'voice' || '' => null,
    'campaigns' => 'campaign',
    _ => first,
  };
}

final mockBackendProvider = Provider<MockBackend>((ref) {
  final b = MockBackend();
  ref.onDispose(b.dispose);
  return b;
});

T _pick<T>(Ref ref, T Function(MockBackend) mock, T Function(ApiClient) api) =>
    ref.watch(useMockProvider)
    ? mock(ref.watch(mockBackendProvider))
    : api(ref.watch(apiClientProvider));

final authRepoProvider = Provider<AuthRepository>(
  (ref) => ref.watch(useMockProvider)
      ? MockAuthRepository()
      : ApiAuthRepository(
          ref.watch(apiClientProvider),
          ref.watch(secureStoreProvider),
        ),
);

final googleAuthProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(),
);

final sessionProvider = AsyncNotifierProvider<SessionNotifier, bool>(
  SessionNotifier.new,
);

class SessionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.watch(authRepoProvider).hasSession();
  }

  /// Google account picker → backend session. Returns
  /// [GoogleSignInOutcome.registrationRequired] for a new Google account; call
  /// [completeGoogleRegistration] with the business details next.
  Future<GoogleSignInOutcome> signInWithGoogle() async {
    final idToken = ref.read(useMockProvider)
        ? 'mock-id-token'
        : await ref.read(googleAuthProvider).signIn();
    final outcome = await ref
        .read(authRepoProvider)
        .signInWithGoogle(idToken: idToken);
    if (outcome == GoogleSignInOutcome.signedIn) {
      // Existing account: its business is already set up.
      await _prefs?.setOnboarded(true);
      ref.read(dataVersionProvider.notifier).bump();
      state = const AsyncValue.data(true);
    }
    return outcome;
  }

  /// Creates the account for the Google user from [signInWithGoogle].
  /// New accounts then go through onboarding.
  Future<void> completeGoogleRegistration({
    required String businessName,
    required String phone,
    String? referralCode,
  }) async {
    final google = ref.read(googleAuthProvider);
    final idToken = ref.read(useMockProvider)
        ? 'mock-id-token'
        : (await google.currentIdToken() ?? await google.signIn());
    await ref
        .read(authRepoProvider)
        .signInWithGoogle(
          idToken: idToken,
          businessName: businessName,
          phone: phone,
          referralCode: referralCode,
        );
    ref.read(dataVersionProvider.notifier).bump();
    state = const AsyncValue.data(true);
  }

  Future<void> requestOtp({required String phone}) async {
    await ref.read(authRepoProvider).requestOtp(phone: phone);
  }

  Future<void> login({required String phone, required String otp}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepoProvider).login(phone: phone, otp: otp);
      // Logging into an existing account: its business is already set up
      // (registration goes through onboarding instead).
      await _prefs?.setOnboarded(true);
      ref.read(dataVersionProvider.notifier).bump();
      return true;
    });
  }

  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
    String? referralCode,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepoProvider)
          .register(
            phone: phone,
            businessName: businessName,
            otp: otp,
            referralCode: referralCode,
          );
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
      await _unregisterPush();
      await ref.read(authRepoProvider).logout();
      await ref.read(googleAuthProvider).signOut();
      await _clearLocalUserState();
      return false;
    });
  }

  /// Deletes the account on the server. On failure the session is kept and
  /// the error is rethrown so the UI can say so instead of pretending.
  Future<void> deleteAccount() async {
    final previous = state;
    state = const AsyncValue.loading();
    try {
      await _unregisterPush();
      await ref.read(authRepoProvider).deleteAccount();
      await ref.read(googleAuthProvider).signOut();
    } catch (_) {
      state = previous;
      rethrow;
    }
    await _clearLocalUserState();
    state = const AsyncValue.data(false);
  }

  LocalPrefs? get _prefs {
    try {
      return ref.read(localPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _unregisterPush() async {
    try {
      final token = ref.read(pushServiceProvider).currentToken;
      if (token != null) {
        await ref.read(deviceRepoProvider).unregisterDevice(token);
      }
      await PushService.deleteToken();
    } catch (_) {}
  }

  /// Nothing from the previous account may leak into the next login.
  Future<void> _clearLocalUserState() async {
    await _prefs?.reset();
    ref.invalidate(activeCampaignProvider);
    ref.read(dataVersionProvider.notifier).bump();
  }
}

final businessRepoProvider = Provider<BusinessRepository>(
  (ref) => _pick(ref, MockBusinessRepository.new, ApiBusinessRepository.new),
);
final knowledgeRepoProvider = Provider<KnowledgeRepository>(
  (ref) => _pick(ref, MockKnowledgeRepository.new, ApiKnowledgeRepository.new),
);
final leadRepoProvider = Provider<LeadRepository>(
  (ref) => _pick(ref, MockLeadRepository.new, ApiLeadRepository.new),
);
final leadSourceRepoProvider = Provider<LeadSourceRepository>(
  (ref) =>
      _pick(ref, MockLeadSourceRepository.new, ApiLeadSourceRepository.new),
);
final callRepoProvider = Provider<CallRepository>(
  (ref) => _pick(ref, MockCallRepository.new, ApiCallRepository.new),
);
final campaignRepoProvider = Provider<CampaignRepository>(
  (ref) => _pick(ref, MockCampaignRepository.new, ApiCampaignRepository.new),
);
final followUpRepoProvider = Provider<FollowUpRepository>(
  (ref) => _pick(ref, MockFollowUpRepository.new, ApiFollowUpRepository.new),
);
final callbackRepoProvider = Provider<CallbackRepository>(
  (ref) => _pick(ref, MockCallbackRepository.new, ApiCallbackRepository.new),
);
final usageRepoProvider = Provider<UsageRepository>(
  (ref) => _pick(ref, MockUsageRepository.new, ApiUsageRepository.new),
);
final notificationRepoProvider = Provider<NotificationRepository>(
  (ref) =>
      _pick(ref, MockNotificationRepository.new, ApiNotificationRepository.new),
);
final referralRepoProvider = Provider<ReferralRepository>(
  (ref) => _pick(ref, MockReferralRepository.new, ApiReferralRepository.new),
);
final dashboardRepoProvider = Provider<DashboardRepository>(
  (ref) => _pick(ref, MockDashboardRepository.new, ApiDashboardRepository.new),
);
final voiceSessionRepoProvider = Provider<VoiceSessionRepository>(
  (ref) => _pick(
    ref,
    (_) => MockVoiceSessionRepository(),
    ApiVoiceSessionRepository.new,
  ),
);
final deviceRepoProvider = Provider<DeviceRepository>(
  (ref) => _pick(ref, (_) => MockDeviceRepository(), ApiDeviceRepository.new),
);

final backendEventsProvider = Provider<BackendEvents>((ref) {
  if (ref.watch(useMockProvider)) return ref.watch(mockBackendProvider);
  final events = PushBackendEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// Services
final whatsappServiceProvider = Provider<WhatsAppService>(
  (_) => const WhatsAppDeepLinkService(),
);
final crashReportingProvider = Provider<CrashReportingService>(
  (_) => SafeCrashReportingService(),
);
final analyticsProvider = Provider<AnalyticsService>(
  (_) => DebugAnalyticsService(),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(
    // The owner's choice, else the phone's language (as the app does).
    strings: () => S(
      ref.read(languageProvider) ??
          AppLang.fromCode(PlatformDispatcher.instance.locale.languageCode),
    ),
  ),
);

final pushServiceProvider = Provider<PushService>((ref) {
  final deviceRepo = ref.watch(deviceRepoProvider);
  final router = ref.watch(routerProvider);
  final events = ref.watch(backendEventsProvider);
  final service = PushService(
    registerToken: (token, platform) =>
        deviceRepo.registerDevice(token: token, platform: platform),
    onRoute: (route) => openDeepLink(router, route),
    onData: (data) {
      // Every push means server state changed: refresh open screens.
      if (events is PushBackendEvents) {
        events.add(DataChangedEvent(data['type'] as String? ?? 'unknown'));
      }
    },
    crash: ref.watch(crashReportingProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final pushServiceInitializerProvider = Provider<void>((ref) {
  final session = ref.watch(sessionProvider);
  final isAuthed = session.asData?.value ?? false;
  if (isAuthed) {
    final push = ref.read(pushServiceProvider);
    push.init();
  }
});

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

/// The home results card: this week vs last week.
final weekResultsProvider = FutureProvider<ResultsSummary>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(dashboardRepoProvider).results(ResultsRange.week);
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

final leadConsentHistoryProvider =
    FutureProvider.family<List<ConsentEvent>, String>((ref, id) {
      ref.watch(dataVersionProvider);
      return ref.watch(leadRepoProvider).consentHistory(id);
    });

final leadCallsProvider = FutureProvider.family<List<Call>, String>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(callRepoProvider).forLead(id);
});

final callProvider = FutureProvider.family<Call, String>(
  (ref, id) => ref.watch(callRepoProvider).get(id),
);

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

final referralsProvider = FutureProvider<ReferralSummary>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(referralRepoProvider).get();
});

/// Reads the Play install referrer (once, then cached in prefs).
final installReferrerServiceProvider = Provider<InstallReferrerService>((ref) {
  LocalPrefs? prefs;
  try {
    prefs = ref.watch(localPrefsProvider);
  } catch (_) {}
  return InstallReferrerService(prefs);
});

/// Referral code this install came with (prefills the signup field).
final installReferralCodeProvider = FutureProvider<String?>(
  (ref) => ref.watch(installReferrerServiceProvider).referralCode(),
);

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(notificationRepoProvider).list();
});

/// Speed-to-lead form and webhooks (Customers → Get leads automatically).
final leadSourcesProvider = FutureProvider<List<LeadSource>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(leadSourceRepoProvider).list();
});

final newLeadsProvider = FutureProvider<List<Lead>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(leadRepoProvider).newLeads();
});

/// Live campaign (if any) – kept in sync from backend progress events.
final activeCampaignProvider = NotifierProvider<ActiveCampaign, Campaign?>(
  ActiveCampaign.new,
);

class ActiveCampaign extends Notifier<Campaign?> {
  @override
  Campaign? build() {
    final sub = ref.watch(backendEventsProvider).stream.listen((e) {
      if (e is CampaignProgressEvent) state = e.campaign;
      // Remote pushes carry no campaign body: re-read it.
      if (e is DataChangedEvent && e.scope == 'campaign') _load();
    });
    ref.onDispose(sub.cancel);
    _load();
    return null;
  }

  void _load() => unawaited(
    ref
        .read(campaignRepoProvider)
        .active()
        .then((c) {
          if (c != null) state = c;
        })
        .catchError((_) {}),
  );

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

final workflowProvider = Provider<WorkflowTemplate>(
  (ref) => ref.watch(businessTemplateProvider).workflow,
);

/// Employee display name – never falls back to a hardcoded persona.
final employeeNameProvider = Provider<String>(
  (ref) => ref.watch(agentProvider).value?.name ?? Brand.employeeFallbackName,
);

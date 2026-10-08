import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/services/notifications/push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth implements AuthRepository {
  bool session = false;
  final calls = <String>[];
  Object? failWith;

  Future<void> _maybeFail() async {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<bool> hasSession() async => session;
  @override
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
  }) async => GoogleSignInOutcome.signedIn;
  @override
  Future<void> requestOtp({required String phone}) async =>
      calls.add('otp:$phone');
  @override
  Future<void> login({required String phone, required String otp}) async {
    await _maybeFail();
    calls.add('login:$phone:$otp');
    session = true;
  }

  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
  }) async {
    await _maybeFail();
    calls.add('register:$phone:$businessName:$otp');
    session = true;
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
    session = false;
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    session = false;
  }
}

class _Devices implements DeviceRepository {
  final unregistered = <String>[];
  @override
  Future<void> registerDevice({
    required String token,
    String? platform,
  }) async {}
  @override
  Future<void> unregisterDevice(String token) async => unregistered.add(token);
}

/// PushService that already holds an FCM token.
class _Push extends PushService {
  _Push() : super(registerToken: (_, _) async {}, onRoute: (_) {});
  @override
  String? get currentToken => 'fcm_tok';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionNotifier', () {
    late _Auth auth;
    late _Devices devices;
    late ProviderContainer c;

    setUp(() {
      auth = _Auth();
      devices = _Devices();
      final backend = MockBackend();
      c = ProviderContainer(
        overrides: [
          useMockProvider.overrideWithValue(true),
          mockBackendProvider.overrideWithValue(backend),
          authRepoProvider.overrideWithValue(auth),
          deviceRepoProvider.overrideWithValue(devices),
          pushServiceProvider.overrideWithValue(_Push()),
        ],
      );
      addTearDown(() {
        c.dispose();
        backend.dispose();
      });
    });

    test('starts from the repository session', () async {
      expect(await c.read(sessionProvider.future), isFalse);
    });

    test('requestOtp, login and register update the session', () async {
      await c.read(sessionProvider.future);
      final n = c.read(sessionProvider.notifier);
      final v0 = c.read(dataVersionProvider);

      await n.requestOtp(phone: '9830012345');
      await n.login(phone: '9830012345', otp: '123456');
      expect(c.read(sessionProvider).value, isTrue);
      expect(c.read(dataVersionProvider), v0 + 1);

      await n.register(phone: '98', businessName: 'Biz', otp: '1');
      expect(auth.calls, [
        'otp:9830012345',
        'login:9830012345:123456',
        'register:98:Biz:1',
      ]);
      expect(c.read(dataVersionProvider), v0 + 2);
    });

    test('failed login surfaces an error state', () async {
      await c.read(sessionProvider.future);
      auth.failWith = const ApiException('Wrong OTP', statusCode: 400);
      await c.read(sessionProvider.notifier).login(phone: '1', otp: '0');
      final s = c.read(sessionProvider);
      expect(s.hasError, isTrue);
      expect(s.error.toString(), 'Wrong OTP');
    });

    test('logout unregisters the push token then signs out', () async {
      auth.session = true;
      expect(await c.read(sessionProvider.future), isTrue);
      await c.read(sessionProvider.notifier).logout();
      expect(devices.unregistered, ['fcm_tok']);
      expect(auth.calls, ['logout']);
      expect(c.read(sessionProvider).value, isFalse);
    });

    test('deleteAccount unregisters the device and signs out', () async {
      auth.session = true;
      await c.read(sessionProvider.future);
      await c.read(sessionProvider.notifier).deleteAccount();
      expect(devices.unregistered, ['fcm_tok']);
      expect(auth.calls, ['delete']);
      expect(c.read(sessionProvider).value, isFalse);
    });

    test('forceLogout drops the session without calling the backend', () async {
      auth.session = true;
      await c.read(sessionProvider.future);
      await c.read(sessionProvider.notifier).forceLogout();
      expect(c.read(sessionProvider).value, isFalse);
      expect(auth.calls, isEmpty);
    });
  });

  group('production wiring (USE_MOCK=false)', () {
    test('repositories resolve to the API implementations', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = LocalPrefs(await SharedPreferences.getInstance());
      final c = ProviderContainer(
        overrides: [
          useMockProvider.overrideWithValue(false),
          localPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(authRepoProvider), isA<ApiAuthRepository>());
      expect(c.read(businessRepoProvider), isA<ApiBusinessRepository>());
      expect(c.read(leadRepoProvider), isA<ApiLeadRepository>());
      expect(c.read(callRepoProvider), isA<ApiCallRepository>());
      expect(c.read(campaignRepoProvider), isA<ApiCampaignRepository>());
      expect(c.read(followUpRepoProvider), isA<ApiFollowUpRepository>());
      expect(
        c.read(voiceSessionRepoProvider),
        isA<ApiVoiceSessionRepository>(),
      );
      expect(c.read(deviceRepoProvider), isA<ApiDeviceRepository>());
      expect(c.read(backendEventsProvider), isNot(isA<MockBackend>()));
    });

    test('an auth failure from the API client forces logout', () async {
      final auth = _Auth()..session = true;
      final c = ProviderContainer(
        overrides: [
          useMockProvider.overrideWithValue(false),
          authRepoProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(sessionProvider.future), isTrue);

      // No LocalPrefs override: the client must still build.
      final api = c.read(apiClientProvider);
      api.onAuthFailure!();
      expect(c.read(sessionProvider).value, isFalse);
    });
  });
}

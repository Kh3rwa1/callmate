import 'package:callpilot/core/config/app_env.dart';
import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/routing/deep_link.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/services/crash/crash_reporting_service.dart';
import 'package:callpilot/services/notifications/push_service.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends SecureStore {
  String? access = 'expired_access';
  String? refresh = 'refresh_token';
  int clears = 0;

  @override
  Future<String?> accessToken() async => access;
  @override
  Future<String?> refreshToken() async => refresh;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    this.access = access;
    if (refresh != null) this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    clears++;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

DioException _offline(RequestOptions o) =>
    DioException(requestOptions: o, type: DioExceptionType.connectionError);

class _AuthRepo implements AuthRepository {
  _AuthRepo({this.deleteFails = false});
  final bool deleteFails;
  bool session = true;

  @override
  Future<bool> hasSession() async => session;
  @override
  Future<void> requestOtp({required String phone}) async {}
  @override
  Future<void> login({required String phone, required String otp}) async =>
      session = true;
  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
  }) async => session = true;
  @override
  Future<void> logout() async => session = false;
  @override
  Future<void> deleteAccount() async {
    if (deleteFails) throw const ApiException('Server unavailable');
    session = false;
  }
}

class _Sink implements CrashSink {
  final errors = <String>[];
  final logs = <String>[];
  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object> context = const {},
  }) async => errors.add('$error|$reason|$fatal|$context');
  @override
  Future<void> log(String message) async => logs.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ApiClient.retryDelay = Duration.zero);

  group('ApiClient keeps the session unless the server rejects it', () {
    test('network failure during refresh keeps tokens', () async {
      final store = _Store();
      var authFailures = 0;
      final client = ApiClient(
        store,
        baseUrl: 'https://api.test',
        onAuthFailure: () => authFailures++,
      );
      client.dio.httpClientAdapter = _Adapter((o) async {
        if (o.path == '/auth/refresh') throw _offline(o);
        return _json('{"message":"expired"}', 401);
      });

      await expectLater(
        client.get('/leads', (d) => d),
        throwsA(isA<ApiException>()),
      );
      expect(store.clears, 0);
      expect(store.refresh, 'refresh_token');
      expect(authFailures, 0);
    });

    test('server 5xx during refresh keeps tokens', () async {
      final store = _Store();
      final client = ApiClient(store, baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async {
        if (o.path == '/auth/refresh') return _json('{}', 503);
        return _json('{}', 401);
      });
      await expectLater(client.get('/leads', (d) => d), throwsA(anything));
      expect(store.clears, 0);
    });

    test('rejected refresh (401) clears tokens and logs out', () async {
      final store = _Store();
      var authFailures = 0;
      final client = ApiClient(
        store,
        baseUrl: 'https://api.test',
        onAuthFailure: () => authFailures++,
      );
      client.dio.httpClientAdapter = _Adapter((o) async => _json('{}', 401));
      await expectLater(client.get('/leads', (d) => d), throwsA(anything));
      expect(store.clears, 1);
      expect(authFailures, 1);
    });

    test('401 from /auth/* never triggers a refresh', () async {
      final store = _Store();
      final paths = <String>[];
      final client = ApiClient(store, baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async {
        paths.add(o.path);
        return _json('{"message":"Invalid code"}', 401);
      });
      await expectLater(
        client.post('/auth/login', (d) => d, data: {'otp': '000000'}),
        throwsA(isA<ApiException>()),
      );
      expect(paths, ['/auth/login']);
      expect(store.clears, 0);
    });
  });

  group('ApiClient network resilience', () {
    test('GET is retried once after a transient network error', () async {
      var calls = 0;
      final client = ApiClient(_Store(), baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async {
        calls++;
        if (calls == 1) throw _offline(o);
        return _json('{"ok":true}', 200);
      });
      final res = await client.get('/leads', (d) => d as Map);
      expect(res['ok'], isTrue);
      expect(calls, 2);
    });

    test('POST is never retried automatically', () async {
      var calls = 0;
      final client = ApiClient(_Store(), baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async {
        calls++;
        throw _offline(o);
      });
      await expectLater(
        client.post('/calls', (d) => d),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
      );
      expect(calls, 1);
    });

    test('send timeout gets an upload-specific message', () async {
      final client = ApiClient(_Store(), baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter(
        (o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.sendTimeout,
        ),
      );
      await expectLater(
        client.post('/leads/import', (d) => d),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'msg',
            contains('Upload'),
          ),
        ),
      );
    });
  });

  group('ApiAuthRepository.logout', () {
    test('revokes the refresh token server-side, then clears', () async {
      final store = _Store();
      final client = ApiClient(store, baseUrl: 'https://api.test');
      Object? body;
      client.dio.httpClientAdapter = _Adapter((o) async {
        if (o.path == '/auth/logout') body = o.data;
        return _json('{"success":true}', 200);
      });
      await ApiAuthRepository(client, store).logout();
      expect(body, {'refresh_token': 'refresh_token'});
      expect(store.clears, 1);
    });

    test('still clears locally when offline', () async {
      final store = _Store();
      final client = ApiClient(store, baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async => throw _offline(o));
      await ApiAuthRepository(client, store).logout();
      expect(store.clears, 1);
    });
  });

  group('AppEnv release guard', () {
    test('a release build with no flavor refuses to start', () {
      expect(
        AppEnv.configError(
          flavor: AppFlavor.dev,
          useMock: false,
          apiBaseUrl: '',
          releaseMode: true,
        ),
        contains('env/prod.json'),
      );
    });

    test('debug dev builds and mock release builds are allowed', () {
      expect(
        AppEnv.configError(
          flavor: AppFlavor.dev,
          useMock: false,
          apiBaseUrl: '',
        ),
        isNull,
      );
      expect(
        AppEnv.configError(
          flavor: AppFlavor.dev,
          useMock: true,
          apiBaseUrl: '',
          releaseMode: true,
        ),
        isNull,
      );
    });
  });

  group('Session state', () {
    Future<ProviderContainer> container(_AuthRepo repo) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await LocalPrefs.create();
      final c = ProviderContainer(
        overrides: [
          localPrefsProvider.overrideWithValue(prefs),
          useMockProvider.overrideWithValue(true),
          authRepoProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sessionProvider.future);
      return c;
    }

    test('failed account deletion keeps the session and rethrows', () async {
      final c = await container(_AuthRepo(deleteFails: true));
      await c.read(localPrefsProvider).setOnboarded(true);
      await expectLater(
        c.read(sessionProvider.notifier).deleteAccount(),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(sessionProvider).value, isTrue);
      expect(c.read(localPrefsProvider).onboarded, isTrue);
    });

    test('logout forgets the previous account\'s onboarding', () async {
      final c = await container(_AuthRepo());
      await c.read(localPrefsProvider).setOnboarded(true);
      await c.read(sessionProvider.notifier).logout();
      expect(c.read(sessionProvider).value, isFalse);
      expect(c.read(localPrefsProvider).onboarded, isFalse);
    });

    test('logging into an existing account skips onboarding', () async {
      final c = await container(_AuthRepo()..session = false);
      await c
          .read(sessionProvider.notifier)
          .login(phone: '+919830012345', otp: '123456');
      expect(c.read(localPrefsProvider).onboarded, isTrue);
    });
  });

  group('PushService', () {
    test('foreground push forwards its data so screens refresh', () async {
      final data = <Map<String, dynamic>>[];
      final service = PushService(
        registerToken: (_, _) async {},
        onRoute: (_) {},
        onData: data.add,
      );
      await service.handleForeground(
        const RemoteMessage(data: {'type': 'hot_lead', 'route': '/leads/1'}),
      );
      expect(data.single['type'], 'hot_lead');
    });

    test('init is idempotent', () async {
      final service = PushService(
        registerToken: (_, _) async {},
        onRoute: (_) {},
      );
      final a = service.init();
      final b = service.init();
      expect(identical(a, b), isTrue);
      await a;
    });
  });

  group('openDeepLink', () {
    GoRouter router() => GoRouter(
      initialLocation: '/home',
      routes: [
        for (final p in [
          '/home',
          '/leads',
          '/leads/:id',
          '/followups',
          '/followups/:id',
          '/calls',
          '/callbacks',
        ])
          GoRoute(path: p, builder: (_, _) => const SizedBox()),
      ],
    );

    String top(GoRouter r) =>
        r.routerDelegate.currentConfiguration.last.matchedLocation;

    Future<GoRouter> mount(WidgetTester t) async {
      final r = router();
      await t.pumpWidget(MaterialApp.router(routerConfig: r));
      return r;
    }

    testWidgets('detail routes keep their tab underneath', (t) async {
      final r = await mount(t);
      openDeepLink(r, '/leads/42');
      await t.pumpAndSettle();
      final stack = r.routerDelegate.currentConfiguration.matches
          .map((m) => m.matchedLocation)
          .toList();
      expect(stack.first, '/leads');
      expect(top(r), '/leads/42');
    });

    testWidgets('external or malformed routes fall back to home', (t) async {
      final r = await mount(t);
      r.go('/calls');
      await t.pumpAndSettle();
      openDeepLink(r, 'https://evil.example');
      await t.pumpAndSettle();
      expect(top(r), '/home');
    });
  });

  group('SafeCrashReportingService sink', () {
    test('only scrubbed data reaches the sink', () async {
      final sink = _Sink();
      SafeCrashReportingService(sink: sink)
        ..reportError(
          Exception('call to 9830012345 failed'),
          StackTrace.current,
          reason: 'token Bearer abc.def',
          context: {'phone': '9830012345', 'screen': 'leads'},
          fatal: true,
        )
        ..log('lead 9830012345');
      await Future<void>.delayed(Duration.zero);
      expect(sink.errors.single, isNot(contains('9830012345')));
      expect(sink.errors.single, contains('[PHONE_REDACTED]'));
      expect(sink.errors.single, contains('Bearer [TOKEN_REDACTED]'));
      expect(sink.errors.single, contains('true'));
      expect(sink.errors.single, isNot(contains('phone')));
      expect(sink.logs.single, 'lead [PHONE_REDACTED]');
    });

    test('a failing sink never throws into the app', () {
      final service = SafeCrashReportingService(sink: _ThrowingSink());
      expect(() => service.reportError(Exception('x'), null), returnsNormally);
    });
  });
}

class _ThrowingSink implements CrashSink {
  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object> context = const {},
  }) => Future.error(StateError('sink down'));
  @override
  Future<void> log(String message) => Future.error(StateError('sink down'));
}

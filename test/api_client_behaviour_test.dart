import 'dart:convert';

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends SecureStore {
  _Store({this.access = 'old', this.refresh = 'r1'});
  String? access;
  String? refresh;
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

typedef _Handler = Future<ResponseBody> Function(RequestOptions o);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final _Handler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

({ApiClient client, _Adapter adapter, _Store store, List<int> failures}) _make(
  _Handler handler, {
  _Store? store,
}) {
  final s = store ?? _Store();
  final failures = <int>[];
  final client = ApiClient(
    s,
    baseUrl: 'https://api.callpilot.test',
    onAuthFailure: () => failures.add(1),
  );
  final adapter = _Adapter(handler);
  client.dio.httpClientAdapter = adapter;
  return (client: client, adapter: adapter, store: s, failures: failures);
}

void main() {
  group('ApiClient auth headers', () {
    test('sends bearer token and flavor header', () async {
      final t = _make((o) async => _json({'ok': true}, 200));
      final res = await t.client.get('/x', (d) => d['ok'] as bool);
      expect(res, isTrue);
      final req = t.adapter.requests.single;
      expect(req.headers['Authorization'], 'Bearer old');
      expect(req.headers['X-App-Flavor'], 'dev');
    });

    test('omits Authorization when there is no access token', () async {
      final t = _make((o) async => _json({}, 200), store: _Store(access: null));
      await t.client.get('/x', (d) => d);
      expect(t.adapter.requests.single.headers['Authorization'], isNull);
    });

    test('uses the server URL override from local prefs', () async {
      SharedPreferences.setMockInitialValues({
        'config.server_url': 'https://override.test',
      });
      final prefs = LocalPrefs(await SharedPreferences.getInstance());
      final client = ApiClient(_Store(), prefs: prefs);
      expect(client.dio.options.baseUrl, 'https://override.test');
    });
  });

  group('ApiClient 401 handling', () {
    test(
      'without a refresh token it fails fast and signals auth failure',
      () async {
        final t = _make(
          (o) async => _json({'message': 'nope'}, 401),
          store: _Store(refresh: null),
        );
        await expectLater(
          t.client.get('/x', (d) => d),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isAuth, 'isAuth', isTrue)
                .having((e) => e.message, 'message', contains('expired')),
          ),
        );
        expect(t.failures, hasLength(1));
        expect(
          t.adapter.requests.where((r) => r.path == '/auth/refresh'),
          isEmpty,
        );
      },
    );

    test('a retried request that is still 401 is not retried again', () async {
      final t = _make((o) async {
        if (o.path == '/auth/refresh') {
          return _json({'access_token': 'new'}, 200);
        }
        return _json({'message': 'still no'}, 401);
      });
      await expectLater(
        t.client.get('/x', (d) => d),
        throwsA(isA<ApiException>()),
      );
      final paths = t.adapter.requests.map((r) => r.path).toList();
      expect(paths, ['/x', '/auth/refresh', '/x']);
      // Refresh succeeded, so the refresh token is kept and no logout happens.
      expect(t.store.access, 'new');
      expect(t.store.refresh, 'r1');
      expect(t.failures, isEmpty);
    });

    test('the single-flight resets so a later 401 refreshes again', () async {
      var refreshes = 0;
      final t = _make((o) async {
        if (o.path == '/auth/refresh') {
          refreshes++;
          return _json({
            'access_token': 'a$refreshes',
            'refresh_token': 'r${refreshes + 1}',
          }, 200);
        }
        final auth = o.headers['Authorization'];
        // Each access token is only good for one request.
        if (auth == 'Bearer a$refreshes' && o.extra['retried'] == true) {
          return _json({'ok': true}, 200);
        }
        return _json({}, 401);
      });

      expect(await t.client.get('/one', (d) => d['ok']), isTrue);
      expect(await t.client.get('/two', (d) => d['ok']), isTrue);
      expect(refreshes, 2);
      expect(t.store.refresh, 'r3');
      final refreshBodies = t.adapter.requests
          .where((r) => r.path == '/auth/refresh')
          .map((r) => (r.data as Map)['refresh_token'])
          .toList();
      expect(refreshBodies, ['r1', 'r2']);
    });

    test('a malformed refresh response clears tokens and logs out', () async {
      final t = _make((o) async {
        if (o.path == '/auth/refresh') return _json({'oops': 1}, 200);
        return _json({}, 401);
      });
      await expectLater(
        t.client.get('/x', (d) => d),
        throwsA(isA<ApiException>()),
      );
      expect(t.store.clears, 1);
      expect(t.failures, hasLength(1));
    });
  });

  group('ApiClient error mapping', () {
    test('connection errors become network ApiExceptions', () async {
      final t = _make(
        (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'offline',
        ),
      );
      await expectLater(
        t.client.post('/x', (d) => d, data: {'a': 1}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('server message is surfaced with its status code', () async {
      final t = _make((o) async => _json({'message': 'Lead not found'}, 404));
      await expectLater(
        t.client.patch('/leads/1', (d) => d, data: {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Lead not found')
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.toString(), 'toString', 'Lead not found'),
        ),
      );
    });

    test('bodies without a message fall back to a generic error', () async {
      final t = _make((o) async => _json(['x'], 500));
      await expectLater(
        t.client.delete('/leads/1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('went wrong'))
              .having((e) => e.isAuth, 'isAuth', isFalse),
        ),
      );
    });

    test('successful verbs map response bodies', () async {
      final t = _make((o) async => _json({'method': o.method}, 200));
      expect(await t.client.post('/p', (d) => d['method']), 'POST');
      expect(await t.client.patch('/p', (d) => d['method']), 'PATCH');
      await t.client.delete('/p');
      expect(t.adapter.requests.last.method, 'DELETE');
      await t.client.get('/q', (d) => d, query: {'limit': 5});
      expect(t.adapter.requests.last.queryParameters, {'limit': 5});
    });
  });
}

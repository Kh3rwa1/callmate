import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/storage/secure_store.dart';

class FakeSecureStore extends SecureStore {
  String? _access = 'initial_access_token';
  String? _refresh = 'valid_refresh_token';
  int clearCallCount = 0;

  @override
  Future<String?> accessToken() async => _access;

  @override
  Future<String?> refreshToken() async => _refresh;

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    _access = access;
    if (refresh != null) _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    clearCallCount++;
  }
}

void main() {
  group('ApiClient single-flight token refresh', () {
    test('concurrent 401s coalesce into exactly one refresh call and retry', () async {
      final store = FakeSecureStore();
      int refreshCallCount = 0;
      int logoutCallCount = 0;

      final client = ApiClient(
        store,
        baseUrl: 'https://api.callpilot.test',
        onAuthFailure: () => logoutCallCount++,
      );

      // Custom adapter to intercept HTTP requests
      client.dio.httpClientAdapter = _MockHttpAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCallCount++;
          // Simulate latency in refresh endpoint
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return ResponseBody.fromString(
            '{"access_token": "new_access_token", "refresh_token": "new_refresh_token"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        // Protected endpoint: reject initial_access_token with 401
        final authHeader = options.headers['Authorization'] as String?;
        if (authHeader == 'Bearer initial_access_token') {
          return ResponseBody.fromString(
            '{"message": "Unauthorized"}',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        } else if (authHeader == 'Bearer new_access_token') {
          return ResponseBody.fromString(
            '{"status": "ok", "path": "${options.path}"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        return ResponseBody.fromString('{"message": "Forbidden"}', 403);
      });

      // Fire 2 concurrent requests that will both receive 401 initially
      final future1 = client.get<String>('/resource-1', (d) => d['status'] as String);
      final future2 = client.get<String>('/resource-2', (d) => d['status'] as String);

      final results = await Future.wait([future1, future2]);

      expect(results, equals(['ok', 'ok']));
      expect(refreshCallCount, equals(1), reason: 'Concurrent 401s must coalesce into a single refresh call');
      expect(logoutCallCount, equals(0), reason: 'Successful refresh must not trigger logout');
      expect(await store.accessToken(), equals('new_access_token'));
    });

    test('failed refresh clears store and triggers onAuthFailure logout cleanly', () async {
      final store = FakeSecureStore();
      int refreshCallCount = 0;
      int logoutCallCount = 0;

      final client = ApiClient(
        store,
        baseUrl: 'https://api.callpilot.test',
        onAuthFailure: () => logoutCallCount++,
      );

      client.dio.httpClientAdapter = _MockHttpAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCallCount++;
          return ResponseBody.fromString('{"message": "Invalid refresh token"}', 401);
        }
        return ResponseBody.fromString('{"message": "Unauthorized"}', 401);
      });

      expect(
        () => client.get('/protected', (d) => d),
        throwsA(isA<ApiException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refreshCallCount, equals(1));
      expect(logoutCallCount, equals(1));
      expect(store.clearCallCount, equals(1));
      expect(await store.accessToken(), isNull);
    });
  });
}

class _MockHttpAdapter implements HttpClientAdapter {
  _MockHttpAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<dynamic>? requestStream, Future<void>? cancelFuture) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

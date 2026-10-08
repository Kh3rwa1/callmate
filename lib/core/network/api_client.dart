import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../storage/local_prefs.dart';
import '../storage/secure_store.dart';

/// User-presentable API error. Screens show [message]; details stay in logs.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  bool get isAuth => statusCode == 401;
  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

/// Authenticated Dio client for OUR backend.
class ApiClient {
  ApiClient(
    this._store, {
    String? baseUrl,
    LocalPrefs? prefs,
    this.onAuthFailure,
  }) : dio = Dio(
         BaseOptions(
           baseUrl:
               baseUrl ??
               // A stored override is a dev-only convenience; staging/prod
               // always use the compiled-in backend.
               (AppEnv.flavor == AppFlavor.dev ? prefs?.serverUrl : null) ??
               AppEnv.effectiveApiBaseUrl,
           connectTimeout: const Duration(seconds: 12),
           sendTimeout: const Duration(seconds: 60),
           receiveTimeout: const Duration(seconds: 20),
           headers: {'Accept': 'application/json'},
         ),
       ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _store.accessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          options.headers['X-App-Flavor'] = AppEnv.flavor.name;
          handler.next(options);
        },
        onError: (e, handler) async {
          final req = e.requestOptions;
          // Idempotent reads get one quick retry on flaky mobile networks.
          if (req.method == 'GET' &&
              _isTransient(e) &&
              req.extra['netRetried'] != true) {
            req.extra['netRetried'] = true;
            await Future<void>.delayed(retryDelay);
            try {
              return handler.resolve(await dio.fetch(req));
            } on DioException catch (retryError) {
              return handler.next(retryError);
            }
          }
          // A 401 from /auth/* means bad OTP/credentials, not an expired
          // session, so never try to refresh there.
          if (e.response?.statusCode == 401 &&
              !req.path.startsWith('/auth/') &&
              req.extra['retried'] != true) {
            final ok = await _refresh();
            if (ok) {
              final token = await _store.accessToken();
              final req = e.requestOptions..extra['retried'] = true;
              if (token != null) {
                req.headers['Authorization'] = 'Bearer $token';
              }
              try {
                return handler.resolve(await dio.fetch(req));
              } catch (_) {}
            }
          }
          handler.next(e);
        },
      ),
    );
    if (kDebugMode) {
      // Log method + path + status only – never bodies (may contain transcripts/PII).
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (r, h) {
            debugPrint(
              '[api] ${r.requestOptions.method} ${r.requestOptions.path} → ${r.statusCode}',
            );
            h.next(r);
          },
          onError: (e, h) {
            debugPrint(
              '[api] ${e.requestOptions.method} ${e.requestOptions.path} ✗ ${e.response?.statusCode ?? e.type.name}',
            );
            h.next(e);
          },
        ),
      );
    }
  }

  final SecureStore _store;
  final Dio dio;
  final VoidCallback? onAuthFailure;

  /// Pause before retrying a GET that failed on the network.
  @visibleForTesting
  static Duration retryDelay = const Duration(milliseconds: 600);

  static bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout;

  Future<bool>? _refreshFlight;

  Future<bool> _refresh() {
    if (_refreshFlight != null) return _refreshFlight!;
    _refreshFlight = _executeRefresh().whenComplete(() {
      _refreshFlight = null;
    });
    return _refreshFlight!;
  }

  Future<bool> _executeRefresh() async {
    final r = await _store.refreshToken();
    if (r == null) {
      onAuthFailure?.call();
      return false;
    }
    try {
      final refreshDio = Dio(
        BaseOptions(
          baseUrl: dio.options.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'application/json'},
        ),
      )..httpClientAdapter = dio.httpClientAdapter;
      final res = await refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': r},
      );
      final data = res.data as Map;
      await _store.saveTokens(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String?,
      );
      return true;
    } on DioException catch (e) {
      // Only a definitive rejection ends the session. Offline, timeouts and
      // 5xx keep the tokens so the user isn't forced back through OTP.
      final status = e.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        await _store.clear();
        onAuthFailure?.call();
      }
      return false;
    } catch (_) {
      // Malformed refresh response: the stored refresh token is unusable.
      await _store.clear();
      onAuthFailure?.call();
      return false;
    }
  }

  Future<T> _wrap<T>(
    Future<Response<dynamic>> Function() f,
    T Function(dynamic) map,
  ) async {
    try {
      final res = await f();
      return map(res.data);
    } on DioException catch (e) {
      throw _toApi(e);
    }
  }

  ApiException _toApi(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError ||
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.transformTimeout:
        return const ApiException(
          'No connection. Check your internet and try again.',
          code: 'network',
        );
      case DioExceptionType.sendTimeout:
        return const ApiException(
          'Upload took too long. Check your internet and try again.',
          code: 'network',
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          "Couldn't establish a secure connection. Try another network.",
          code: 'network',
        );
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.', code: 'cancelled');
      case DioExceptionType.badResponse || DioExceptionType.unknown:
        break;
    }
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final msg = body is Map && body['message'] is String
        ? body['message'] as String
        : null;
    if (status == 401) {
      return ApiException(
        'Your session expired. Please log in again.',
        statusCode: status,
      );
    }
    return ApiException(
      msg ?? 'Something went wrong. Try again.',
      statusCode: status,
    );
  }

  Future<T> get<T>(
    String path,
    T Function(dynamic) map, {
    Map<String, dynamic>? query,
  }) => _wrap(() => dio.get(path, queryParameters: query), map);

  Future<T> post<T>(String path, T Function(dynamic) map, {Object? data}) =>
      _wrap(() => dio.post(path, data: data), map);

  Future<T> patch<T>(String path, T Function(dynamic) map, {Object? data}) =>
      _wrap(() => dio.patch(path, data: data), map);

  Future<void> delete(String path) => _wrap(() => dio.delete(path), (_) {});
}

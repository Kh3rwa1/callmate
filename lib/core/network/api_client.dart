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
  ApiClient(this._store, {String? baseUrl, LocalPrefs? prefs})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? prefs?.serverUrl ?? AppEnv.effectiveApiBaseUrl,
          connectTimeout: const Duration(seconds: 12),
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
          if (e.response?.statusCode == 401 && e.requestOptions.extra['retried'] != true) {
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
            debugPrint('[api] ${r.requestOptions.method} ${r.requestOptions.path} → ${r.statusCode}');
            h.next(r);
          },
          onError: (e, h) {
            debugPrint('[api] ${e.requestOptions.method} ${e.requestOptions.path} ✗ ${e.response?.statusCode ?? e.type.name}');
            h.next(e);
          },
        ),
      );
    }
  }

  final SecureStore _store;
  final Dio dio;

  Future<bool> _refresh() async {
    final r = await _store.refreshToken();
    if (r == null) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: dio.options.baseUrl)).post('/auth/refresh', data: {'refresh_token': r});
      final data = res.data as Map;
      await _store.saveTokens(access: data['access_token'] as String, refresh: data['refresh_token'] as String?);
      return true;
    } catch (_) {
      await _store.clear();
      return false;
    }
  }

  Future<T> _wrap<T>(Future<Response<dynamic>> Function() f, T Function(dynamic) map) async {
    try {
      final res = await f();
      return map(res.data);
    } on DioException catch (e) {
      throw _toApi(e);
    }
  }

  ApiException _toApi(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ApiException('No connection. Check your internet and try again.', code: 'network');
    }
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final msg = body is Map && body['message'] is String ? body['message'] as String : null;
    if (status == 401) return ApiException('Your session expired. Please log in again.', statusCode: status);
    return ApiException(msg ?? 'Something went wrong. Try again.', statusCode: status);
  }

  Future<T> get<T>(String path, T Function(dynamic) map, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: query), map);

  Future<T> post<T>(String path, T Function(dynamic) map, {Object? data}) => _wrap(() => dio.post(path, data: data), map);

  Future<T> patch<T>(String path, T Function(dynamic) map, {Object? data}) => _wrap(() => dio.patch(path, data: data), map);

  Future<void> delete(String path) => _wrap(() => dio.delete(path), (_) {});
}

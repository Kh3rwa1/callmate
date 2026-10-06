import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-side secrets: ONLY our own backend session tokens.
/// Sarvam credentials never touch the device.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _access = 'auth.access_token';
  static const _refresh = 'auth.refresh_token';

  Future<String?> accessToken() => _s.read(key: _access);
  Future<String?> refreshToken() => _s.read(key: _refresh);

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _s.write(key: _access, value: access);
    if (refresh != null) await _s.write(key: _refresh, value: refresh);
  }

  Future<void> clear() async {
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
  }
}

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test.dart' show TestAuthRepository;

/// The backend refuses the sign-in.
class _Refusing extends TestAuthRepository {
  _Refusing(this.error);
  final ApiException error;
  @override
  Future<void> login({required String phone, required String otp}) async =>
      throw error;
  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
    String? referralCode,
  }) async => throw error;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> container(_Refusing repo) async {
    final prefs = LocalPrefs(await SharedPreferences.getInstance());
    final c = ProviderContainer(
      overrides: [
        authRepoProvider.overrideWithValue(repo),
        useMockProvider.overrideWithValue(false),
        localPrefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    return c;
  }

  // The login screen waits on these calls; a swallowed error left its
  // spinner running forever (seen on a phone with an unregistered number).
  test('a refused login is rethrown and leaves the user signed out', () async {
    const notFound = ApiException(
      'Account not found. Please register first.',
      statusCode: 404,
      code: 'user_not_found',
    );
    final c = await container(_Refusing(notFound));
    await expectLater(
      c.read(sessionProvider.notifier).login(phone: '919749500000', otp: '1'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'user_not_found'),
      ),
    );
    expect(c.read(sessionProvider), const AsyncValue<bool>.data(false));
  });

  test('a refused registration is rethrown too', () async {
    const wrongCode = ApiException(
      'Invalid verification code.',
      statusCode: 400,
      code: 'invalid_otp',
    );
    final c = await container(_Refusing(wrongCode));
    await expectLater(
      c
          .read(sessionProvider.notifier)
          .register(phone: '919749500000', businessName: 'Das Gym', otp: '1'),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(sessionProvider).value, isFalse);
  });
}

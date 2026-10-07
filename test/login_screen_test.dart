import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestAuthRepository implements AuthRepository {
  String? requestedPhone;
  String? loginPhone;
  String? loginOtp;
  String? registerPhone;
  String? registerBiz;
  String? registerOtp;
  bool session = false;

  @override
  Future<bool> hasSession() async => session;

  @override
  Future<void> requestOtp({required String phone}) async {
    requestedPhone = phone;
  }

  @override
  Future<void> login({required String phone, required String otp}) async {
    loginPhone = phone;
    loginOtp = otp;
    session = true;
  }

  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
  }) async {
    registerPhone = phone;
    registerBiz = businessName;
    registerOtp = otp;
    session = true;
  }

  @override
  Future<void> logout() async => session = false;

  @override
  Future<void> deleteAccount() async => session = false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('LoginScreen OTP request and verification flow', (tester) async {
    final testRepo = TestAuthRepository();
    final prefs = await SharedPreferences.getInstance();
    final localPrefs = LocalPrefs(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepoProvider.overrideWithValue(testRepo),
          localPrefsProvider.overrideWithValue(localPrefs),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    // Initial state: phone entry step
    expect(find.text('Sign In to Your Workspace'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);

    // Enter phone number
    await tester.enterText(find.byType(TextField).first, '9830012345');
    await tester.pumpAndSettle();

    // Tap Send OTP
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    // Verify requestOtp was called with normalized phone
    expect(testRepo.requestedPhone, equals('919830012345'));

    // Step 2: OTP screen displayed
    expect(find.text('Verify OTP'), findsOneWidget);
    expect(find.text('Verify & Enter'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget);

    // Enter 6-digit OTP
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pumpAndSettle();

    // Tap Verify & Enter
    await tester.tap(find.text('Verify & Enter'));
    await tester.pumpAndSettle();

    // Verify login was called with correct arguments
    expect(testRepo.loginPhone, equals('919830012345'));
    expect(testRepo.loginOtp, equals('123456'));
    expect(testRepo.session, isTrue);
  });
}

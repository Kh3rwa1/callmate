import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/auth/login_screen.dart';
import 'package:callpilot/services/auth/google_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestAuthRepository implements AuthRepository {
  String? requestedPhone;
  String? loginPhone;
  String? loginOtp;
  String? registerPhone;
  String? registerBiz;
  String? registerOtp;
  bool session = false;
  bool googleAccountExists = false;
  final googleCalls = <Map<String, String?>>[];

  @override
  Future<bool> hasSession() async => session;

  @override
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
  }) async {
    googleCalls.add({
      'token': idToken,
      'business': businessName,
      'phone': phone,
    });
    if (!googleAccountExists && businessName == null) {
      return GoogleSignInOutcome.registrationRequired;
    }
    googleAccountExists = true;
    session = true;
    return GoogleSignInOutcome.signedIn;
  }

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

class FakeGoogleAuth extends GoogleAuthService {
  bool cancel = false;
  int signOuts = 0;

  @override
  Future<String> signIn() async {
    if (cancel) throw const GoogleSignInCancelled();
    return 'firebase-id-token';
  }

  @override
  Future<String?> currentIdToken() async => 'firebase-id-token';

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(TestAuthRepository, FakeGoogleAuth)> pumpLogin(
    WidgetTester tester, {
    bool accountExists = false,
  }) async {
    final repo = TestAuthRepository()..googleAccountExists = accountExists;
    final google = FakeGoogleAuth();
    final prefs = LocalPrefs(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepoProvider.overrideWithValue(repo),
          googleAuthProvider.overrideWithValue(google),
          useMockProvider.overrideWithValue(false),
          localPrefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    return (repo, google);
  }

  testWidgets('existing Google account signs straight in', (tester) async {
    final (repo, _) = await pumpLogin(tester, accountExists: true);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Send OTP'), findsNothing);

    await tester.ensureVisible(find.text('Continue with Google'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(repo.googleCalls.single['token'], 'firebase-id-token');
    expect(repo.session, isTrue);
  });

  testWidgets('new Google account finishes with business name and phone', (
    tester,
  ) async {
    final (repo, _) = await pumpLogin(tester);

    await tester.ensureVisible(find.text('Continue with Google'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Set Up Your Business'), findsOneWidget);
    expect(repo.session, isFalse);

    await tester.ensureVisible(find.text('Create Account'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('business or company name'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Apex Coaching');
    await tester.enterText(find.byType(TextField).at(1), '9830012345');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(repo.googleCalls.last, {
      'token': 'firebase-id-token',
      'business': 'Apex Coaching',
      'phone': '919830012345',
    });
    expect(repo.session, isTrue);
  });

  testWidgets('closing the Google picker is not an error', (tester) async {
    final (repo, google) = await pumpLogin(tester);
    google.cancel = true;

    await tester.ensureVisible(find.text('Continue with Google'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(repo.googleCalls, isEmpty);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('switching Google account signs out of the new one', (
    tester,
  ) async {
    final (_, google) = await pumpLogin(tester);
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Use a different Google account'));

    await tester.pumpAndSettle();

    await tester.tap(find.text('Use a different Google account'));
    await tester.pumpAndSettle();

    expect(google.signOuts, 1);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/referrals/invite_screen.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:callpilot/services/attribution/install_referrer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends SecureStore {
  @override
  Future<String?> accessToken() async => 'access';
  @override
  Future<String?> refreshToken() async => 'refresh';
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
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

ResponseBody _json(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _summary = ReferralSummary(
  code: 'ABC234',
  link: 'https://api.test/get?ref=ABC234',
  bonusMinutes: 200,
  signedUp: 3,
  rewarded: 1,
  minutesEarned: 200,
);

void main() {
  group('install referrer parsing', () {
    test('reads the code from utm_campaign or ref', () {
      expect(
        refCodeFromInstallReferrer('utm_source=landing&utm_campaign=ABC234'),
        'ABC234',
      );
      expect(refCodeFromInstallReferrer('ref=abc-234'), 'ABC234');
      expect(
        refCodeFromInstallReferrer('utm_source=landing&utm_campaign=none'),
        isNull,
      );
      expect(
        refCodeFromInstallReferrer('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
      expect(refCodeFromInstallReferrer(null), isNull);
      expect(refCodeFromInstallReferrer(''), isNull);
      expect(refCodeFromInstallReferrer('utm_campaign=ABC23O'), isNull);
    });

    test('normalizes codes like the backend', () {
      expect(normalizeReferralCode(' abc 234 '), 'ABC234');
      expect(normalizeReferralCode('ABC2345'), isNull);
      expect(normalizeReferralCode('I0OL11'), isNull);
    });
  });

  group('InstallReferrerService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('reads the Play referrer once and remembers the code', () async {
      final prefs = LocalPrefs(await SharedPreferences.getInstance());
      var reads = 0;
      final service = InstallReferrerService(
        prefs,
        read: () async {
          reads++;
          return 'utm_source=landing&utm_campaign=XYZ789';
        },
      );
      expect(await service.referralCode(), 'XYZ789');
      expect(await service.referralCode(), 'XYZ789');
      expect(reads, 1);
      expect(prefs.installReferralCode, 'XYZ789');
    });

    test('an organic install is remembered as no code', () async {
      final prefs = LocalPrefs(await SharedPreferences.getInstance());
      var reads = 0;
      final service = InstallReferrerService(
        prefs,
        read: () async {
          reads++;
          return 'utm_source=google-play&utm_medium=organic';
        },
      );
      expect(await service.referralCode(), isNull);
      expect(await service.referralCode(), isNull);
      expect(reads, 1);
    });

    test('a failed read is retried next time', () async {
      final prefs = LocalPrefs(await SharedPreferences.getInstance());
      var fail = true;
      final service = InstallReferrerService(
        prefs,
        read: () async {
          if (fail) throw Exception('play services unavailable');
          return 'utm_campaign=ABC234';
        },
      );
      expect(await service.referralCode(), isNull);
      expect(prefs.installReferrerChecked, isFalse);
      fail = false;
      expect(await service.referralCode(), 'ABC234');
    });
  });

  group('API', () {
    test('ReferralSummary.fromJson is defensive', () {
      final r = ReferralSummary.fromJson({
        'code': 'ABC234',
        'link': 'https://x/get?ref=ABC234',
        'signed_up': 2,
        'rewarded': '1',
        'minutes_earned': 200.0,
      });
      expect(r.code, 'ABC234');
      expect(r.signedUp, 2);
      expect(r.rewarded, 1);
      expect(r.minutesEarned, 200);
      expect(r.bonusMinutes, 200);
    });

    test('signup sends referral_code only when there is one', () async {
      final store = _Store();
      final client = ApiClient(store, baseUrl: 'https://api.test');
      final bodies = <Map>[];
      client.dio.httpClientAdapter = _Adapter((o) async {
        bodies.add(o.data as Map);
        return _json('{"access_token":"a","refresh_token":"r"}');
      });
      final repo = ApiAuthRepository(client, store);
      await repo.register(phone: '919830012345', businessName: 'B', otp: '1');
      await repo.register(
        phone: '919830012345',
        businessName: 'B',
        otp: '1',
        referralCode: 'ABC234',
      );
      await repo.signInWithGoogle(idToken: 't', businessName: 'B', phone: '9');
      await repo.signInWithGoogle(
        idToken: 't',
        businessName: 'B',
        phone: '9',
        referralCode: 'ABC234',
      );
      expect(bodies[0].containsKey('referral_code'), isFalse);
      expect(bodies[1]['referral_code'], 'ABC234');
      expect(bodies[2].containsKey('referral_code'), isFalse);
      expect(bodies[3]['referral_code'], 'ABC234');
    });

    test('GET /referrals', () async {
      final client = ApiClient(_Store(), baseUrl: 'https://api.test');
      String? path;
      client.dio.httpClientAdapter = _Adapter((o) async {
        path = o.path;
        return _json(
          '{"code":"ABC234","link":"l","bonus_minutes":150,"signed_up":1,"rewarded":0,"minutes_earned":0}',
        );
      });
      final r = await ApiReferralRepository(client).get();
      expect(path, '/referrals');
      expect(r.bonusMinutes, 150);
      expect(r.signedUp, 1);
    });

    test('mock repository serves demo stats', () async {
      final b = MockBackend();
      final r = await MockReferralRepository(b).get();
      expect(normalizeReferralCode(r.code), r.code);
      expect(r.link, contains('ref=${r.code}'));
      b.dispose();
    });
  });

  test('WhatsApp share link has no recipient and an encoded message', () {
    final uri = whatsAppShareUri(' Hi & try https://x/get?ref=ABC234 ');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/');
    expect(uri.queryParameters['text'], 'Hi & try https://x/get?ref=ABC234');
  });

  test('invite strings exist in all three languages', () {
    for (final lang in AppLang.values) {
      final s = S(lang);
      expect(s.inviteAndEarn, isNotEmpty);
      expect(s.referralCodeOptional, isNotEmpty);
      final msg = s.inviteMessage('https://x/get?ref=ABC234', 'ABC234', 200);
      expect(msg, contains('https://x/get?ref=ABC234'));
      expect(msg, contains('ABC234'));
      expect(msg, contains('200'));
    }
    expect(const S(AppLang.hi).inviteAndEarn, isNot(S.en.inviteAndEarn));
    expect(const S(AppLang.bn).inviteAndEarn, isNot(S.en.inviteAndEarn));
  });

  testWidgets('Invite screen shows code, stats and share actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useMockProvider.overrideWithValue(false),
          referralsProvider.overrideWith((ref) async => _summary),
        ],
        child: const MaterialApp(home: InviteScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Invite & earn'), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.text('Give 200 minutes, get 200 minutes'), findsOneWidget);
    expect(find.text('Share on WhatsApp'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Signed up'), findsOneWidget);
    expect(find.text('Minutes earned'), findsOneWidget);
  });
}

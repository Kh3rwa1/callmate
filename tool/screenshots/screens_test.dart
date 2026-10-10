// Renders real screens (mock data, real fonts, real mascot images) to PNGs
// for design review, in light + dark and English + Hindi + Bengali.
//   flutter test --update-goldens tool/screenshots
// Output: tool/screenshots/out/<variant>/<screen>.png (gitignored).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/settings.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/l10n/s.dart';

import '../../test/helpers/app_harness.dart';

class _SignedOut implements AuthRepository {
  @override
  Future<bool> hasSession() async => false;
  @override
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
    String? referralCode,
  }) async => GoogleSignInOutcome.registrationRequired;
  @override
  Future<void> requestOtp({required String phone}) async {}
  @override
  Future<void> login({required String phone, required String otp}) async {}
  @override
  Future<void> register({
    required String phone,
    required String businessName,
    required String otp,
    String? referralCode,
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> deleteAccount() async {}
}

Future<void> _loadFamily(String family, String file, List<String> weights) {
  final loader = FontLoader(family);
  for (final w in weights) {
    final bytes = File('assets/fonts/$file-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  return loader.load();
}

Future<void> _loadFonts() async {
  await _loadFamily('Geist', 'Geist', [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
  ]);
  // Devanagari and Bengali fallbacks.
  const indic = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await _loadFamily('Hind', 'Hind', indic);
  await _loadFamily('HindSiliguri', 'HindSiliguri', indic);
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

/// One look of the app: theme × language.
typedef _Variant = ({String name, ThemeMode theme, AppLang lang});

const List<_Variant> _variants = [
  (name: 'light_en', theme: ThemeMode.light, lang: AppLang.en),
  (name: 'dark_en', theme: ThemeMode.dark, lang: AppLang.en),
  (name: 'light_hi', theme: ThemeMode.light, lang: AppLang.hi),
  (name: 'light_bn', theme: ThemeMode.light, lang: AppLang.bn),
];

/// Screens shot in every variant. A route builder gets the harness so it
/// can point at real mock records; [push] stacks the route on [base] so the
/// screen shows its back button.
typedef _Shot = ({
  String name,
  String base,
  String Function(AppHarness h)? push,
  bool onboarded,
  bool signedOut,
  int settle,
});

_Shot _tab(String name, String route) => (
  name: name,
  base: route,
  push: null,
  onboarded: true,
  signedOut: false,
  settle: 14,
);

_Shot _detail(String name, String Function(AppHarness h) route) => (
  name: name,
  base: '/home',
  push: route,
  onboarded: true,
  signedOut: false,
  settle: 14,
);

_Shot _onboarding(String name, String route, {int settle = 14}) => (
  name: name,
  base: route,
  push: null,
  onboarded: false,
  signedOut: false,
  settle: settle,
);

final List<_Shot> _shots = [
  _tab('home', '/home'),
  _tab('leads', '/leads'),
  _tab('calls', '/calls'),
  _tab('followups', '/followups'),
  _tab('agent', '/agent'),
  _detail('notifications', (_) => '/notifications'),
  _detail('usage', (_) => '/usage'),
  _detail('campaign_new', (_) => '/campaign/new'),
  _detail('import', (_) => '/leads/import'),
  _detail('voice_test', (_) => '/voice-test'),
  _detail('teach', (_) => '/agent/teach'),
  _detail(
    'call_result',
    (h) =>
        '/calls/${h.backend.calls.firstWhere((c) => c.leadScore != null).id}/result',
  ),
  _detail(
    'lead_detail',
    (h) =>
        '/leads/${h.backend.leads.values.firstWhere((l) => l.score != null).id}',
  ),
  _detail(
    'followup_detail',
    (h) => '/followups/${h.backend.followUps.values.first.id}',
  ),
  (
    name: 'login',
    base: '/login',
    push: null,
    onboarded: false,
    signedOut: true,
    settle: 14,
  ),
  _onboarding('onboarding_0_language', '/language'),
  _onboarding('onboarding_1_welcome', '/onboarding'),
  _onboarding('onboarding_2_type', '/onboarding/business-type'),
  _onboarding('onboarding_3_skills', '/onboarding/skills'),
  _onboarding('onboarding_4_details', '/onboarding/details'),
  _onboarding('onboarding_5_offer', '/onboarding/offer'),
  _onboarding('onboarding_6_teach', '/onboarding/teach'),
  // Long enough for the learning sequence to finish and "meet" to show.
  _onboarding('onboarding_7_meet', '/onboarding/create', settle: 40),
  _onboarding('onboarding_8_first_call', '/onboarding/test'),
];

/// Image.asset decodes on a real async thread; without this the mascot is
/// missing from every golden.
Future<void> _decodeImages(WidgetTester t) async {
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final image = (e.widget as Image).image;
      await precacheImage(image, e);
    }
  });
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(_loadFonts);

  for (final v in _variants) {
    for (final shot in _shots) {
      appTest(
        'screenshot ${v.name}/${shot.name}',
        (h) async {
          final t = h.tester;
          t.view.physicalSize = const Size(1080, 2340);
          t.view.devicePixelRatio = 2.75;
          await h.container.read(themeModeProvider.notifier).set(v.theme);
          await h.container.read(languageProvider.notifier).set(v.lang);
          await h.settle(2);
          final push = shot.push;
          if (push != null) await h.push(push(h));
          await h.settle(shot.settle);
          await _decodeImages(t);
          await h.settle(4);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('out/${v.name}/${shot.name}.png'),
          );
        },
        location: shot.base,
        onboarded: shot.onboarded,
        overrides: shot.signedOut
            ? () => [authRepoProvider.overrideWithValue(_SignedOut())]
            : null,
      );
    }
  }
}

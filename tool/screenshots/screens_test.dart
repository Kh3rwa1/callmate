// Renders real screens (mock data, real fonts) to PNGs for design review.
//   flutter test --update-goldens tool/screenshots
// Output: tool/screenshots/out/*.png (gitignored).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/repositories/repositories.dart';

import '../../test/helpers/app_harness.dart';

class _SignedOut implements AuthRepository {
  @override
  Future<bool> hasSession() async => false;
  @override
  Future<GoogleSignInOutcome> signInWithGoogle({
    required String idToken,
    String? businessName,
    String? phone,
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
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> deleteAccount() async {}
}

Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    jakarta.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await jakarta.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytesSync())));
  await icons.load();
}

const _screens = <String, String>{
  'home': '/home',
  'leads': '/leads',
  'calls': '/calls',
  'followups': '/followups',
  'agent': '/agent',
  'notifications': '/notifications',
  'usage': '/usage',
  'campaign_new': '/campaign/new',
  'import': '/leads/import',
  'voice_test': '/voice-test',
};

void main() {
  setUpAll(_loadFonts);

  for (final e in _screens.entries) {
    appTest('screenshot ${e.key}', (h) async {
      final t = h.tester;
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      await h.settle(14);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/${e.key}.png'),
      );
    }, location: e.value);
  }

  for (final (name, route) in [
    ('call_result', (AppHarness h) => '/calls/${h.backend.calls.firstWhere((c) => c.leadScore != null).id}/result'),
    ('lead_detail', (AppHarness h) => '/leads/${h.backend.leads.values.firstWhere((l) => l.score != null).id}'),
    ('followup_detail', (AppHarness h) => '/followups/${h.backend.followUps.values.first.id}'),
  ]) {
    appTest('screenshot $name', (h) async {
      final t = h.tester;
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      await h.push(route(h));
      await h.settle(14);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    });
  }

  appTest('screenshot login', (h) async {
    final t = h.tester;
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    await h.settle(14);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/login.png'));
  }, location: '/login', overrides: () => [authRepoProvider.overrideWithValue(_SignedOut())]);

  appTest('screenshot onboarding', (h) async {
    final t = h.tester;
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    await h.settle(14);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/onboarding.png'));
  }, location: '/onboarding', onboarded: false);
}

import 'package:callpilot/app.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/routing/app_router.dart' show routerProvider;
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/services/voice/mock_voice_agent_service.dart';
import 'package:callpilot/services/voice/voice_agent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real [CallPilotApp] (real router, real screens) on top of the
/// in-memory [MockBackend], on a tall 800 px wide surface (the test font's
/// square glyphs are much wider than real fonts, so phone widths overflow).
class AppHarness {
  AppHarness._(this.tester, this.container, this.backend, this.prefs);

  final WidgetTester tester;
  final ProviderContainer container;
  final MockBackend backend;
  final LocalPrefs prefs;

  GoRouter get router => container.read(routerProvider);

  String get location =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  /// Pumps enough frames for mock latency (~300 ms per call) and page
  /// transitions to finish. Never uses pumpAndSettle: several widgets run
  /// repeating animations.
  Future<void> settle([int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> go(String location) async {
    router.go(location);
    await settle();
  }

  Future<void> push(String location) async {
    router.push(location);
    await settle();
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text).first);

  Future<void> _dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Flush outstanding mock latency / voice timers before closing streams.
    await tester.pump(const Duration(seconds: 30));
    backend.dispose();
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Voice service used in widget tests: scripted mock, never the real SDK.
VoiceAgentService testVoiceService() => MockVoiceAgentService(
  agentName: 'Riya',
  agentRole: 'Admissions Counsellor',
  businessName: 'ABC Coaching Centre',
);

Future<AppHarness> pumpApp(
  WidgetTester tester, {
  String location = '/home',
  bool onboarded = true,
  MockBackend? backend,
  List<Override> overrides = const [],
  VoiceAgentService Function()? voice,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'onboarding.completed': onboarded});
  final prefs = LocalPrefs(await SharedPreferences.getInstance());
  final b = backend ?? MockBackend();
  final container = ProviderContainer(
    overrides: [
      useMockProvider.overrideWithValue(true),
      mockBackendProvider.overrideWithValue(b),
      localPrefsProvider.overrideWithValue(prefs),
      voiceAgentServiceProvider.overrideWith((ref) {
        final s = (voice ?? testVoiceService)();
        ref.onDispose(s.dispose);
        return s;
      }),
      ...overrides,
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CallPilotApp(),
    ),
  );
  final h = AppHarness._(tester, container, b, prefs);
  h.router.go(location);
  await h.settle();
  return h;
}

/// `testWidgets` that boots the app at [location] and always tears it down
/// cleanly (no pending timers) even when the body fails.
void appTest(
  String description,
  Future<void> Function(AppHarness h) body, {
  String location = '/home',
  bool onboarded = true,
  MockBackend Function()? backend,
  List<Override> Function()? overrides,
  VoiceAgentService Function()? voice,
}) {
  testWidgets(description, (tester) async {
    final h = await pumpApp(
      tester,
      location: location,
      onboarded: onboarded,
      backend: backend?.call(),
      overrides: overrides?.call() ?? const [],
      voice: voice,
    );
    try {
      await body(h);
    } finally {
      await h._dispose();
    }
  });
}

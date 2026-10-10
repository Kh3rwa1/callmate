import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_controller.dart';
import 'package:callpilot/features/onboarding/onboarding_screens.dart';
import 'package:callpilot/features/voice_test/voice_test_screen.dart';
import 'package:callpilot/services/voice/voice_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Business repository whose first save fails, to exercise the inline error.
class _FailOnceBusinessRepository extends MockBusinessRepository {
  _FailOnceBusinessRepository(super.b);
  int saves = 0;

  @override
  Future<Business> saveBusiness(Business business) async {
    saves++;
    if (saves == 1) throw StateError('backend unavailable');
    return super.saveBusiness(business);
  }
}

/// 2 PM in India (inside calling hours) and 11 PM (outside).
DateTime _istAfternoon() => DateTime.utc(2026, 10, 10, 8, 30);
DateTime _istNight() => DateTime.utc(2026, 10, 10, 17, 30);

void main() {
  group('First run (3 steps)', () {
    appTest(
      'owner hears the AI in 3 steps: type → name + voice → call me now',
      (h) async {
        // ---- 1/3 Business type: one tap moves on.
        expect(find.byType(BusinessTypeScreen), findsOneWidget);
        expect(find.byKey(const Key('onboarding-dots')), findsOneWidget);
        expect(find.textContaining('6 quick steps'), findsNothing);
        expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
        await h.tapText('Clinic');
        expect(h.location, '/onboarding/name');
        expect(
          h.container.read(onboardingProvider).category,
          BusinessCategory.clinic,
        );

        // ---- 2/3 Name (prefilled from sign-up) + voice.
        final field = find.byType(TextFormField);
        expect(
          h.tester.widget<TextFormField>(field).controller!.text,
          h.backend.business.name,
        );
        await h.tester.enterText(field, '');
        await h.tapText('Continue');
        expect(find.text('Please enter your business name'), findsOneWidget);
        expect(h.location, '/onboarding/name');
        await h.tester.enterText(field, 'Sunrise Clinic');
        await h.tapText("Man's voice");
        final d = h.container.read(onboardingProvider);
        expect(d.maleVoiceChosen, isTrue);
        expect(isMaleVoice(d.employeeVoice), isTrue);
        await h.tapText('Continue');
        expect(h.location, '/onboarding/hear');

        // Business + employee exist, with the business type's defaults.
        expect(h.backend.business.name, 'Sunrise Clinic');
        expect(h.backend.business.category, BusinessCategory.clinic);
        expect(h.backend.agent.status, AgentStatus.active);
        expect(isMaleVoice(h.backend.agent.voice), isTrue);
        expect(h.backend.agent.name, d.resolvedEmployeeName);
        expect(h.backend.agent.skills, isNotEmpty);
        expect(h.prefs.onboarded, isTrue);

        // ---- 3/3 Hear your AI: number prefilled, one tap.
        expect(find.byType(HearAiScreen), findsOneWidget);
        await h.settle(4);
        await h.tapText('Call me now');
        expect(h.prefs.heardAi, isTrue);
        await h.tapText('Go to home');
        expect(h.location, '/home');
        expect(find.byType(HomeScreen), findsOneWidget);
      },
      location: '/onboarding',
      onboarded: false,
      overrides: () => [clockProvider.overrideWithValue(_istAfternoon)],
    );

    appTest(
      'outside calling hours the last step offers the in-app voice test',
      (h) async {
        expect(find.byKey(const Key('outside-hours')), findsOneWidget);
        expect(find.text('Call me now'), findsNothing);
        await h.tap(find.textContaining('Talk in-app with'));
        expect(h.location, '/voice-test');
        expect(
          h.tester
              .widget<VoiceTestScreen>(find.byType(VoiceTestScreen))
              .fromOnboarding,
          isTrue,
        );
      },
      location: '/onboarding/hear',
      onboarded: false,
      overrides: () => [clockProvider.overrideWithValue(_istNight)],
    );

    appTest(
      'skip on the last step goes home',
      (h) async {
        await h.tap(find.byKey(const Key('hear-skip')));
        expect(h.prefs.onboarded, isTrue);
        expect(h.location, '/home');
      },
      location: '/onboarding/hear',
      onboarded: false,
    );

    appTest(
      'back button returns to the type step and keeps the choice',
      (h) async {
        await h.tapText('Retail');
        expect(h.location, '/onboarding/name');
        await h.tap(find.byTooltip('Back'));
        expect(h.location, '/onboarding');
        expect(
          h.container.read(onboardingProvider).category,
          BusinessCategory.retail,
        );
        // Continue is enabled once a type is picked.
        await h.tapText('Continue');
        expect(h.location, '/onboarding/name');
      },
      location: '/onboarding',
      onboarded: false,
    );

    appTest(
      'old step links land on the new steps',
      (h) async {
        await h.go('/onboarding/skills');
        expect(h.location, '/onboarding/name');
        await h.go('/onboarding/business-type');
        expect(h.location, '/onboarding');
        await h.go('/onboarding/test');
        expect(h.location, '/onboarding/hear');
      },
      location: '/onboarding',
      onboarded: false,
    );

    late _FailOnceBusinessRepository failing;
    appTest(
      'a failed save shows the error on the step and recovers',
      (h) async {
        await h.tapText('Continue');
        expect(find.byKey(const Key('setup-error')), findsOneWidget);
        expect(h.location, '/onboarding/name');
        expect(h.prefs.onboarded, isFalse);
        await h.tapText('Continue');
        expect(failing.saves, 2);
        expect(h.location, '/onboarding/hear');
      },
      location: '/onboarding/name',
      onboarded: false,
      overrides: () => [
        businessRepoProvider.overrideWith((ref) {
          return failing = _FailOnceBusinessRepository(
            ref.watch(mockBackendProvider),
          );
        }),
      ],
    );
  });
}

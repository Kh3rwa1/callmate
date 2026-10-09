import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/templates/templates.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_controller.dart';
import 'package:callpilot/features/onboarding/onboarding_screens.dart';
import 'package:callpilot/features/voice_test/voice_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Business repository whose first save fails, to exercise retry UI.
///
/// The failure is delayed past the "learning" animation: CreateAgentScreen
/// only attaches a listener to the save future after ~1.7 s, so an earlier
/// failure escapes as an unhandled async error (see report).
class _FailOnceBusinessRepository extends MockBusinessRepository {
  _FailOnceBusinessRepository(super.b);
  int saves = 0;

  @override
  Future<Business> saveBusiness(Business business) async {
    saves++;
    if (saves == 1) {
      await Future<void>.delayed(const Duration(seconds: 3));
      throw StateError('backend unavailable');
    }
    return super.saveBusiness(business);
  }
}

void main() {
  Finder field(int i) => find.byType(TextFormField).at(i);

  group('Onboarding flow', () {
    appTest(
      'owner completes onboarding end to end',
      (h) async {
        // ---- Welcome
        expect(find.byType(WelcomeScreen), findsOneWidget);
        await h.tapText('Create My AI Employee');
        expect(h.location, '/onboarding/business-type');
        expect(find.text('1/6'), findsOneWidget);

        // ---- Business type: Continue is disabled until a category is picked.
        await h.tapText('Continue');
        expect(h.location, '/onboarding/business-type');
        await h.tapText('Clinic');
        final draft = h.container.read(onboardingProvider);
        expect(draft.category, BusinessCategory.clinic);
        expect(draft.skills, isNotEmpty, reason: 'defaults pre-selected');
        await h.tapText('Continue');
        expect(h.location, '/onboarding/skills');

        // ---- Skills: toggling updates the suggested employee.
        await h.tapText('Sales');
        expect(
          h.container.read(onboardingProvider).skills,
          contains(EmployeeSkill.sales),
        );
        final role = h.container.read(onboardingProvider).suggestedAgent.role;
        final article = 'AEIOU'.contains(role[0]) ? 'an' : 'a';
        expect(
          find.text('We\'ll set up $article $role for you.'),
          findsOneWidget,
        );
        await h.tapText('Continue');
        expect(h.location, '/onboarding/details');

        // ---- Business details: prefilled from sign-up; name is required.
        expect(
          h.tester.widget<TextFormField>(field(0)).controller!.text,
          isNotEmpty,
        );
        await h.tester.enterText(field(0), '');
        await h.tapText('Continue');
        expect(find.text('Please enter your business name'), findsOneWidget);
        expect(h.location, '/onboarding/details');
        await h.tester.enterText(field(0), 'Sunrise Clinic');
        await h.tester.enterText(field(1), '5 Lake Road, Kolkata');
        await h.tapText('Continue');
        expect(h.location, '/onboarding/offer');

        // ---- Offer: offerings required, phone numbers validated.
        expect(
          h.tester.widget<TextFormField>(field(3)).controller!.text,
          '5 Lake Road, Kolkata',
          reason: 'location is prefilled from the address',
        );
        await h.tester.enterText(field(4), '123');
        await h.tapText('Continue');
        expect(find.textContaining('Add at least one'), findsOneWidget);
        expect(find.text('Enter a valid mobile number'), findsOneWidget);
        await h.tester.enterText(field(0), 'Consultation, Dental care');
        await h.tester.enterText(field(1), '₹500 per visit');
        await h.tester.enterText(field(2), 'Mon–Sat 9–8');
        await h.tester.enterText(field(4), '98300 12345');
        await h.tester.enterText(field(5), '98300 99999');
        await h.tapText('Continue');
        expect(h.location, '/onboarding/teach');

        // ---- Teach: nothing added yet → "Skip for now".
        expect(find.text('Skip for now'), findsOneWidget);

        // Website sheet validates the URL.
        await h.tapText('Add website');
        await h.tester.enterText(find.byType(TextFormField).last, 'nope');
        await h.tapText('Add to your AI\'s knowledge');
        expect(find.text('Enter a valid website'), findsOneWidget);
        await h.tester.enterText(
          find.byType(TextFormField).last,
          'sunriseclinic.in',
        );
        await h.tapText('Add to your AI\'s knowledge');
        var k = h.container.read(onboardingProvider).knowledge;
        expect(k.single.url, 'https://sunriseclinic.in');

        // FAQ sheet requires some detail and defaults the title.
        await h.tapText('Add FAQ');
        await h.tester.enterText(find.byType(TextFormField).last, 'short');
        await h.tapText('Add to your AI\'s knowledge');
        expect(find.text('Add a little more detail'), findsOneWidget);
        await h.tester.enterText(
          find.byType(TextFormField).last,
          'Q: Do you take walk-ins?\nA: Yes, before noon.',
        );
        await h.tapText('Add to your AI\'s knowledge');
        k = h.container.read(onboardingProvider).knowledge;
        expect(k.map((e) => e.title), ['Website', 'FAQ']);

        // Pasted notes keep a custom title; then remove it again.
        await h.tapText('Paste text');
        await h.tester.enterText(
          find.byType(TextFormField).first,
          'Parking info',
        );
        await h.tester.enterText(
          find.byType(TextFormField).last,
          'Free parking is available behind the clinic.',
        );
        await h.tapText('Add to your AI\'s knowledge');
        expect(find.text('Parking info'), findsOneWidget);
        await h.tap(find.byTooltip('Remove').last);
        expect(find.text('Parking info'), findsNothing);
        expect(h.container.read(onboardingProvider).knowledge, hasLength(2));

        await h.tapText('Import CSV leads later');
        expect(
          find.text('You\'ll be able to import leads right after setup.'),
          findsOneWidget,
        );
        // Let the snack bar (which covers the CTA) time out.
        await h.settle(35);

        await h.tapText('Continue');
        expect(h.location, '/onboarding/create');

        // ---- Create agent: learning phase, then "meet".
        expect(find.byType(CreateAgentScreen), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Meet your AI employee 👋'), findsNothing);
        await h.settle(40);
        expect(find.text('Meet your AI employee 👋'), findsOneWidget);

        // Business + knowledge were persisted.
        expect(h.backend.business.name, 'Sunrise Clinic');
        expect(h.backend.business.category, BusinessCategory.clinic);
        expect(h.backend.business.offerings, ['Consultation', 'Dental care']);
        expect(h.backend.business.whatsappNumber, '98300 12345');
        expect(
          h.backend.knowledge.map((e) => e.title),
          containsAll(['Website', 'FAQ']),
        );

        // Empty name blocks activation.
        await h.tester.enterText(find.byType(TextField).at(0), '');
        await h.settle(2);
        expect(find.text('Name your employee'), findsOneWidget);
        await h.tapText('Activate Employee');
        expect(h.location, '/onboarding/create');

        await h.tester.enterText(find.byType(TextField).at(0), 'Kabir');
        await h.tester.enterText(
          find.byType(TextField).at(1),
          'Front Desk Assistant',
        );
        await h.settle(2);
        expect(find.text('Kabir'), findsWidgets);
        await h.tapText('Activate Employee');
        expect(h.location, '/onboarding/test');
        expect(h.backend.agent.name, 'Kabir');
        expect(h.backend.agent.role, 'Front Desk Assistant');
        expect(h.backend.agent.status, AgentStatus.active);

        // ---- First call screen → dashboard.
        expect(find.byType(FirstCallScreen), findsOneWidget);
        expect(find.text('Talk to Kabir'), findsOneWidget);
        await h.tapText('Go to my dashboard');
        expect(h.prefs.onboarded, isTrue);
        expect(h.location, '/home');
        expect(find.byType(HomeScreen), findsOneWidget);
      },
      location: '/onboarding',
      onboarded: false,
    );

    appTest(
      'back button returns to the previous step',
      (h) async {
        await h.tapText('Create My AI Employee');
        await h.tapText('Retail');
        await h.tapText('Continue');
        expect(h.location, '/onboarding/skills');
        await h.tap(find.byTooltip('Back'));
        expect(h.location, '/onboarding/business-type');
        // Selection survives navigating back.
        expect(
          h.container.read(onboardingProvider).category,
          BusinessCategory.retail,
        );
      },
      location: '/onboarding',
      onboarded: false,
    );

    appTest(
      'skills step requires at least one skill',
      (h) async {
        h.container
            .read(onboardingProvider.notifier)
            .update((d) => d.copyWith(category: BusinessCategory.other));
        await h.settle(2);
        expect(h.container.read(onboardingProvider).skills, isEmpty);
        await h.tapText('Continue');
        expect(h.location, '/onboarding/skills');
        await h.tapText('Follow Up');
        await h.tapText('Continue');
        expect(h.location, '/onboarding/details');
      },
      location: '/onboarding/skills',
      onboarded: false,
    );

    late _FailOnceBusinessRepository failing;
    appTest(
      'create step shows an error and recovers on retry',
      (h) async {
        await h.settle(30);
        expect(
          find.text('We couldn\'t set up your AI employee'),
          findsOneWidget,
        );
        await h.tapText('Try again');
        await h.settle(30);
        expect(failing.saves, 2);
        expect(find.text('Meet your AI employee 👋'), findsOneWidget);
      },
      location: '/onboarding/create',
      onboarded: false,
      overrides: () => [
        businessRepoProvider.overrideWith((ref) {
          return failing = _FailOnceBusinessRepository(
            ref.watch(mockBackendProvider),
          );
        }),
      ],
    );

    appTest(
      'first call CTA opens the in-app voice test',
      (h) async {
        await h.tapText('Talk to ${h.backend.agent.name}');
        expect(h.location, '/voice-test');
        expect(find.byType(VoiceTestScreen), findsOneWidget);
        expect(
          h.tester
              .widget<VoiceTestScreen>(find.byType(VoiceTestScreen))
              .fromOnboarding,
          isTrue,
        );
      },
      location: '/onboarding/test',
      onboarded: false,
    );

    appTest(
      'agent tested shows the shortcut to the dashboard',
      (h) async {
        await h.prefs.setAgentTested(true);
        h.router.go('/onboarding');
        await h.settle();
        h.router.go('/onboarding/test');
        await h.settle();
        await h.tapText('Looks great – go to dashboard');
        expect(h.prefs.onboarded, isTrue);
        expect(h.location, '/home');
      },
      location: '/onboarding/test',
      onboarded: false,
    );
  });
}

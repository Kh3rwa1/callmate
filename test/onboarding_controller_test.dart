import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/templates/templates.dart';
import 'package:callpilot/features/onboarding/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MockBackend backend;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = LocalPrefs(await SharedPreferences.getInstance());
    backend = MockBackend();
    container = ProviderContainer(
      overrides: [
        useMockProvider.overrideWithValue(true),
        mockBackendProvider.overrideWithValue(backend),
        localPrefsProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  OnboardingController ctrl() => container.read(onboardingProvider.notifier);
  OnboardingDraft draft() => container.read(onboardingProvider);

  group('OnboardingDraft', () {
    test('defaults are empty and template falls back to the last one', () {
      const d = OnboardingDraft();
      expect(d.category, isNull);
      expect(d.skills, isEmpty);
      expect(d.knowledge, isEmpty);
      expect(d.template, templateFor(null));
      expect(d.suggestedAgent, d.template.agent);
    });

    test('copyWith keeps unspecified fields', () {
      const d = OnboardingDraft(
        businessName: 'A',
        address: 'B',
        pricing: 'C',
        employeeName: 'Neha',
      );
      final c = d.copyWith(address: 'X', hours: '9-5');
      expect(c.businessName, 'A');
      expect(c.address, 'X');
      expect(c.pricing, 'C');
      expect(c.hours, '9-5');
      expect(c.employeeName, 'Neha');
    });

    test('suggestedAgent follows the chosen skills', () {
      const base = OnboardingDraft(category: BusinessCategory.retail);
      expect(
        base.copyWith(skills: {EmployeeSkill.admissions}).suggestedAgent,
        coachingAgentTemplate,
      );
      expect(
        base.copyWith(skills: {EmployeeSkill.bookAppointments}).suggestedAgent,
        appointmentAgentTemplate,
      );
      expect(
        base.copyWith(skills: {EmployeeSkill.sales}).suggestedAgent,
        salesAgentTemplate,
      );
      expect(
        base
            .copyWith(skills: {EmployeeSkill.customerSupport})
            .suggestedAgent
            .role,
        'Support Assistant',
      );
    });
  });

  group('OnboardingController', () {
    test('selectCategory pre-selects the template default skills', () {
      ctrl().selectCategory(BusinessCategory.coaching);
      expect(draft().category, BusinessCategory.coaching);
      expect(
        draft().skills,
        templateFor(BusinessCategory.coaching).agent.defaultSkills.toSet(),
      );
    });

    test('re-selecting the same category keeps the owner skill choices', () {
      ctrl().selectCategory(BusinessCategory.coaching);
      ctrl().toggleSkill(EmployeeSkill.customerSupport);
      final chosen = draft().skills;
      ctrl().selectCategory(BusinessCategory.coaching);
      expect(draft().skills, chosen);
    });

    test('switching category resets skills to the new defaults', () {
      ctrl().selectCategory(BusinessCategory.coaching);
      ctrl().toggleSkill(EmployeeSkill.customerSupport);
      ctrl().selectCategory(BusinessCategory.clinic);
      expect(
        draft().skills,
        templateFor(BusinessCategory.clinic).agent.defaultSkills.toSet(),
      );
    });

    test('toggleSkill adds then removes a skill', () {
      ctrl().toggleSkill(EmployeeSkill.sales);
      expect(draft().skills, {EmployeeSkill.sales});
      ctrl().toggleSkill(EmployeeSkill.sales);
      expect(draft().skills, isEmpty);
    });

    test('update applies an arbitrary transformation', () {
      ctrl().update((d) => d.copyWith(businessName: 'Sunrise Clinic'));
      expect(draft().businessName, 'Sunrise Clinic');
    });

    test('add and remove knowledge', () {
      const k1 = KnowledgeInput(
        type: KnowledgeType.text,
        title: 'About',
        content: 'We teach NEET.',
      );
      const k2 = KnowledgeInput(
        type: KnowledgeType.website,
        title: 'Site',
        url: 'https://abc.in',
      );
      ctrl().addKnowledge(k1);
      ctrl().addKnowledge(k2);
      expect(draft().knowledge, [k1, k2]);
      ctrl().removeKnowledge(k1);
      expect(draft().knowledge, [k2]);
    });

    test(
      'saveBusiness persists trimmed fields and uploads knowledge',
      () async {
        final before = backend.knowledge.length;
        ctrl().selectCategory(BusinessCategory.clinic);
        ctrl().update(
          (d) => d.copyWith(
            businessName: '  Sunrise Clinic ',
            address: ' 5 Lake Road ',
            offerings: 'Consultation, Dental\nX-Ray, ',
            pricing: '₹500',
            hours: '   ',
            whatsapp: '9830012345',
            humanNumber: '9830099999',
          ),
        );
        ctrl().addKnowledge(
          const KnowledgeInput(
            type: KnowledgeType.text,
            title: 'Notes',
            content: 'Open on Sundays',
          ),
        );

        await ctrl().saveBusiness();

        final b = backend.business;
        expect(b.name, 'Sunrise Clinic');
        expect(b.category, BusinessCategory.clinic);
        expect(b.address, '5 Lake Road');
        expect(b.offerings, ['Consultation', 'Dental', 'X-Ray']);
        expect(b.pricing, '₹500');
        expect(b.whatsappNumber, '9830012345');
        expect(b.humanNumber, '9830099999');
        expect(backend.knowledge.length, before + 1);
        expect(backend.knowledge.first.title, 'Notes');
        expect(draft().knowledge, isEmpty);
      },
    );

    test('saveBusiness keeps the existing name when none is entered', () async {
      final original = backend.business.name;
      await ctrl().saveBusiness();
      expect(backend.business.name, original);
    });

    test(
      'activateEmployee uses template defaults when owner left blanks',
      () async {
        ctrl().selectCategory(BusinessCategory.coaching);
        final agent = await ctrl().activateEmployee();
        final at = draft().suggestedAgent;
        expect(agent.name, at.defaultName);
        expect(agent.role, at.role);
        expect(agent.status, AgentStatus.active);
        expect(agent.templateId, at.id);
        expect(agent.capabilities.first, 'Calling');
        expect(agent.capabilities.last, 'Hot Lead Alerts');
        expect(backend.agent.name, at.defaultName);
      },
    );

    test(
      'activateEmployee applies owner overrides and skill capabilities',
      () async {
        ctrl().selectCategory(BusinessCategory.realEstate);
        ctrl().update(
          (d) => d.copyWith(
            skills: {
              EmployeeSkill.sales,
              EmployeeSkill.bookAppointments,
              EmployeeSkill.customerSupport,
              EmployeeSkill.admissions,
              EmployeeSkill.enquiryHandling,
              EmployeeSkill.makeCalls,
            },
            employeeName: '  Kabir ',
            employeeRole: ' Property Advisor ',
          ),
        );
        final agent = await ctrl().activateEmployee();
        expect(agent.name, 'Kabir');
        expect(agent.role, 'Property Advisor');
        expect(
          agent.skills,
          containsAll(['sales', 'book_appointments', 'make_calls']),
        );
        expect(
          agent.capabilities,
          containsAll([
            'Appointment Booking',
            'Sales Conversations',
            'Customer Support',
            'Admissions Guidance',
            'Enquiry Handling',
            'Callback Scheduling',
          ]),
        );
        // No duplicates.
        expect(agent.capabilities.toSet().length, agent.capabilities.length);
      },
    );

    test(
      'activateEmployee falls back to template skills when none chosen',
      () async {
        ctrl().update((d) => d.copyWith(category: BusinessCategory.coaching));
        final agent = await ctrl().activateEmployee();
        expect(
          agent.skills,
          draft().suggestedAgent.defaultSkills.map((e) => e.wire).toList(),
        );
      },
    );
  });
}

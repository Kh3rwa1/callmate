import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/ai_output.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/templates/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockBackend b;
  setUp(() => b = MockBackend());
  tearDown(() => b.dispose());

  group('JSON round-trips preserve seeded data', () {
    test('Lead', () {
      for (final l in b.leads.values.take(10)) {
        final r = Lead.fromJson(l.toJson());
        expect(r.id, l.id);
        expect(r.name, l.name);
        expect(r.phone, l.phone);
        expect(r.status, l.status);
        expect(r.score?.value, l.score?.value);
        expect(r.score?.temperature, l.score?.temperature);
        expect(r.attributes, l.attributes);
        expect(r.toJson(), l.toJson());
      }
    });

    test('Call', () {
      final c = b.simulateCall(LeadTemperature.hot);
      final r = Call.fromJson(c.toJson());
      expect(r.id, c.id);
      expect(r.status, c.status);
      expect(r.leadScore?.value, c.leadScore?.value);
      expect(r.transcript.lines.length, c.transcript.lines.length);
      expect(r.toJson(), c.toJson());
    });

    test('Business and Agent', () {
      expect(
        Business.fromJson(b.business.toJson()).toJson(),
        b.business.toJson(),
      );
      expect(Agent.fromJson(b.agent.toJson()).toJson(), b.agent.toJson());
    });

    test('Campaign with stats and options', () {
      final c = Campaign(
        id: 'cmp_1',
        agentId: 'agent_1',
        purpose: 'Admissions follow-up',
        status: CampaignStatus.running,
        createdAt: DateTime.utc(2026, 10, 7, 9),
        startedAt: DateTime.utc(2026, 10, 7, 10),
        leadIds: const ['a', 'b'],
        options: const CampaignOptions(notifyHot: false),
        stats: const CampaignStats(total: 4, completed: 1, hot: 1),
        estimatedCostInr: 120,
        recentCallIds: const ['call_1'],
      );
      final r = Campaign.fromJson(c.toJson());
      expect(r.toJson(), c.toJson());
      expect(r.isActive, isTrue);
      expect(r.options.notifyHot, isFalse);
      expect(r.stats.progress, 0.25);
    });
  });

  group('fromJson edge cases', () {
    test('LeadScore derives temperature from value when absent', () {
      expect(
        LeadScore.fromJson({'value': 90}).temperature,
        LeadTemperature.fromScore(90),
      );
      expect(
        LeadScore.fromJson({'value': 90, 'temperature': 'cold'}).temperature,
        LeadTemperature.cold,
      );
    });

    test('AiCallOutput honours explicit temperature and legacy keys', () {
      final o = AiCallOutput.fromJson({
        'lead_score': -5,
        'temperature': 'warm',
        'course_interest': 'NEET',
        'attributes': {'batch': 'evening', 'budget': 50000, 'skip': null},
      });
      expect(o.leadScore, 0);
      expect(o.temperature, LeadTemperature.warm);
      expect(o.interest, 'NEET');
      expect(o.attributes, {'batch': 'evening', 'budget': '50000'});
    });

    test('Campaign defaults when fields are missing', () {
      final c = Campaign.fromJson({'id': 'x'});
      expect(c.languageMode, 'auto');
      expect(c.callingHoursStart, 10);
      expect(c.callingHoursEnd, 19);
      expect(c.stats.progress, 0);
      expect(c.options.scoreLead, isTrue);
    });
  });

  group('copyWith', () {
    test('LeadScore intent labels', () {
      String label(LeadTemperature t) => LeadScore(
        value: 50,
        temperature: t,
        intent: LeadIntent.interested,
      ).intentLabel;
      expect(label(LeadTemperature.hot), 'HIGH INTENT');
      expect(label(LeadTemperature.warm), 'MEDIUM INTENT');
      expect(label(LeadTemperature.cold), 'LOW INTENT');
      expect(label(LeadTemperature.unknown), 'NOT SCORED');
    });

    test('Callback.copyWith changes status/time only', () {
      final c = Callback(
        id: 'cb',
        leadId: 'l',
        leadName: 'Rahul',
        scheduledAt: DateTime(2026, 10, 8, 18),
        note: 'evening',
      );
      final later = DateTime(2026, 10, 9, 18);
      final r = c.copyWith(status: CallbackStatus.done, scheduledAt: later);
      expect(r.status, CallbackStatus.done);
      expect(r.scheduledAt, later);
      expect(r.note, 'evening');
      expect(r.leadName, 'Rahul');
      expect(c.copyWith().scheduledAt, c.scheduledAt);
    });

    test('AppNotification.copyWith marks read', () {
      final n = b.simulateNotification(NotificationType.values.first);
      final r = n.copyWith(read: true);
      expect(r.read, isTrue);
      expect(r.id, n.id);
      expect(r.route, n.route);
      expect(n.copyWith().read, n.read);
    });

    test('CampaignOptions.copyWith', () {
      const o = CampaignOptions();
      final r = o.copyWith(generateWhatsapp: false, recommendCallback: false);
      expect(r.generateWhatsapp, isFalse);
      expect(r.recommendCallback, isFalse);
      expect(r.scoreLead, isTrue);
      expect(r.notifyHot, isTrue);
    });

    test('Campaign.copyWith keeps identity fields', () {
      final c = Campaign(
        id: 'c',
        agentId: 'a',
        purpose: 'p',
        status: CampaignStatus.draft,
        createdAt: DateTime(2026),
        leadIds: const ['x'],
      );
      final r = c.copyWith(status: CampaignStatus.completed);
      expect(r.status, CampaignStatus.completed);
      expect(r.leadIds, ['x']);
      expect(r.purpose, 'p');
    });

    test('Business.copyWith keeps unspecified fields', () {
      final r = b.business.copyWith(name: 'New Name');
      expect(r.name, 'New Name');
      expect(r.category, b.business.category);
      expect(r.address, b.business.address);
      expect(r.offerings, b.business.offerings);
    });

    test('KnowledgeSource.copyWith updates status and progress', () {
      final k = KnowledgeSource(
        id: 'k',
        type: KnowledgeType.pdf,
        title: 'Brochure',
        status: KnowledgeStatus.uploading,
        updatedAt: DateTime(2026),
        progress: 0.2,
      );
      final r = k.copyWith(status: KnowledgeStatus.ready, progress: 1);
      expect(r.status, KnowledgeStatus.ready);
      expect(r.progress, 1);
      expect(r.title, 'Brochure');
      expect(r.updatedAt.isAfter(k.updatedAt), isTrue);
    });
  });

  group('Templates', () {
    test('EmployeeSkill.parse round-trips wire values', () {
      for (final s in EmployeeSkill.values) {
        expect(EmployeeSkill.parse(s.wire), s);
      }
      expect(EmployeeSkill.parse('nope'), isNull);
      expect(EmployeeSkill.parse(null), isNull);
    });

    test('agentForSkills picks a role from the skill mix', () {
      final base = templateFor(BusinessCategory.retail);
      expect(agentForSkills(base, {}), base.agent);
      expect(
        agentForSkills(base, {EmployeeSkill.customerSupport}).roleKind,
        EmployeeRoleKind.support,
      );
      expect(
        agentForSkills(base, {EmployeeSkill.qualifyLeads}),
        salesAgentTemplate,
      );
      expect(
        agentForSkills(base, {
          EmployeeSkill.bookAppointments,
          EmployeeSkill.sales,
        }),
        salesAgentTemplate,
      );
      expect(agentForSkills(base, {EmployeeSkill.followUp}), base.agent);
    });

    test('templateFor falls back for unknown categories', () {
      expect(templateFor(null), businessTemplates.last);
      expect(
        templateFor(BusinessCategory.coaching).category,
        BusinessCategory.coaching,
      );
    });
  });
}

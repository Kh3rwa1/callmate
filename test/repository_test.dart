import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';

void main() {
  late MockBackend backend;
  late MockBusinessRepository businessRepo;
  late MockLeadRepository leadRepo;
  late MockCallRepository callRepo;
  late MockCampaignRepository campaignRepo;
  late MockFollowUpRepository followUpRepo;
  late MockCallbackRepository callbackRepo;
  late MockUsageRepository usageRepo;
  late MockNotificationRepository notificationRepo;
  late MockKnowledgeRepository knowledgeRepo;
  late MockVoiceSessionRepository voiceRepo;

  setUp(() {
    backend = MockBackend();
    businessRepo = MockBusinessRepository(backend);
    leadRepo = MockLeadRepository(backend);
    callRepo = MockCallRepository(backend);
    campaignRepo = MockCampaignRepository(backend);
    followUpRepo = MockFollowUpRepository(backend);
    callbackRepo = MockCallbackRepository(backend);
    usageRepo = MockUsageRepository(backend);
    notificationRepo = MockNotificationRepository(backend);
    knowledgeRepo = MockKnowledgeRepository(backend);
    voiceRepo = MockVoiceSessionRepository();
  });

  tearDown(() {
    backend.dispose();
  });

  group('MockBusinessRepository', () {
    test('getBusiness and saveBusiness updates state', () async {
      final biz = await businessRepo.getBusiness();
      expect(biz, isNotNull);
      expect(biz!.name, isNotEmpty);

      final updated = await businessRepo.saveBusiness(
        biz.copyWith(name: 'Updated Academy'),
      );
      expect(updated.name, 'Updated Academy');

      final refetched = await businessRepo.getBusiness();
      expect(refetched!.name, 'Updated Academy');
    });

    test('getAgent and saveAgent updates agent state', () async {
      final agent = await businessRepo.getAgent();
      expect(agent, isNotNull);

      final updatedAgent = await businessRepo.saveAgent(
        agent!.copyWith(name: 'Aditi'),
      );
      expect(updatedAgent.name, 'Aditi');
    });
  });

  group('MockLeadRepository', () {
    test('list returns paginated leads with filters', () async {
      final page = await leadRepo.list(limit: 5);
      expect(page.items.length, 5);
      expect(page.hasMore, isTrue);

      final hotPage = await leadRepo.list(filter: LeadFilter.hot);
      expect(hotPage.items.every((l) => l.isHot), isTrue);
    });

    test('create and get lead', () async {
      final newLead = await leadRepo.create(
        const NewLeadInput(
          name: 'Arjun Das',
          phone: '919876543210',
          interest: 'NEET 2026',
        ),
      );
      expect(newLead.id, isNotEmpty);
      expect(newLead.name, 'Arjun Das');

      final fetched = await leadRepo.get(newLead.id);
      expect(fetched.phone, '919876543210');
    });

    test('update lead details', () async {
      final leads = await leadRepo.list(limit: 1);
      final lead = leads.items.first;

      final updated = await leadRepo.update(
        lead.copyWith(interest: 'Updated Course'),
      );
      expect(updated.interest, 'Updated Course');
    });

    test('import multiple leads', () async {
      final result = await leadRepo.import([
        const NewLeadInput(name: 'L1', phone: '919800000001'),
        const NewLeadInput(name: 'L2', phone: '919800000002'),
      ]);
      expect(result.imported, 2);
    });
  });

  group('MockCallRepository', () {
    test('list calls with filters and trigger call for lead', () async {
      final calls = await callRepo.list(limit: 10);
      expect(calls.items, isNotEmpty);

      final leads = await leadRepo.list(limit: 1);
      final testLead = leads.items.first;

      final triggeredCall = await callRepo.triggerCall(testLead.id);
      expect(triggeredCall.leadId, testLead.id);
      expect(triggeredCall.status, isNotNull);

      final leadCalls = await callRepo.forLead(testLead.id);
      expect(leadCalls.any((c) => c.id == triggeredCall.id), isTrue);
    });
  });

  group('MockCampaignRepository', () {
    test('create, start, stop campaign and estimate cost', () async {
      final cost = campaignRepo.estimateCostInr(100);
      expect(cost, greaterThan(0));

      final campaign = await campaignRepo.create(
        const CampaignDraft(purpose: 'Admissions 2026', leadIds: ['l1', 'l2']),
      );
      expect(campaign.status, CampaignStatus.draft);

      final started = await campaignRepo.start(campaign.id);
      expect(started.status, CampaignStatus.running);

      final active = await campaignRepo.active();
      expect(active?.id, campaign.id);

      final stopped = await campaignRepo.stop(campaign.id);
      expect(stopped.status, CampaignStatus.stopped);
    });
  });

  group('MockFollowUpRepository & MockCallbackRepository', () {
    test('follow-up list and update', () async {
      final list = await followUpRepo.list(pendingOnly: true);
      expect(list, isNotEmpty);

      final first = list.first;
      final updated = await followUpRepo.update(
        first.copyWith(status: FollowUpStatus.opened),
      );
      expect(updated.status, FollowUpStatus.opened);
    });

    test('callback schedule and markDone', () async {
      final leadId = backend.leads.keys.first;
      final scheduled = await callbackRepo.schedule(
        leadId: leadId,
        at: DateTime.now().add(const Duration(hours: 2)),
        note: 'Discuss scholarship',
      );
      expect(scheduled.status, CallbackStatus.scheduled);

      final done = await callbackRepo.markDone(scheduled.id);
      expect(done.status, CallbackStatus.done);
    });
  });

  group('Usage, Notification, Knowledge & Voice Repositories', () {
    test('usage get returns non-empty plan', () async {
      final u = await usageRepo.get();
      expect(u.subscription.planName, isNotEmpty);
      expect(u.subscription.includedMinutes, greaterThan(0));
    });

    test('notifications list and markRead', () async {
      final notifs = await notificationRepo.list();
      expect(notifs, isNotEmpty);

      final first = notifs.first;
      await notificationRepo.markRead(first.id);
      final refetched = await notificationRepo.list();
      final target = refetched.firstWhere((n) => n.id == first.id);
      expect(target.read, isTrue);
    });

    test('knowledge add, list, and remove', () async {
      final initial = await knowledgeRepo.list();
      expect(initial, isNotEmpty);

      final stream = knowledgeRepo.add(
        const KnowledgeInput(
          type: KnowledgeType.text,
          title: 'Fee Structure',
          content: 'Fee is 50,000 INR per year.',
        ),
      );
      final result = await stream.last;
      expect(result.title, 'Fee Structure');

      await knowledgeRepo.remove(result.id);
      final afterRemove = await knowledgeRepo.list();
      expect(afterRemove.any((k) => k.id == result.id), isFalse);
    });

    test('voiceSessionRepo createTestSession and sendChatMessage', () async {
      final sess = await voiceRepo.createTestSession();
      expect(sess.sessionToken, 'demo');

      final reply = await voiceRepo.sendChatMessage('What is the fee?');
      expect(reply.reply, isNotEmpty);
    });
  });
}

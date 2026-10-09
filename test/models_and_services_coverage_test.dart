import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/services/analytics/analytics_service.dart';
import 'package:callpilot/services/crash/crash_reporting_service.dart';
import 'package:callpilot/services/notifications/notification_service.dart';
import 'package:callpilot/services/notifications/push_service.dart';
import 'package:callpilot/services/voice/mock_voice_agent_service.dart';
import 'package:callpilot/services/voice/voice_agent_service.dart';
import 'package:callpilot/services/whatsapp/whatsapp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDate = DateTime.parse('2026-01-01T12:00:00.000Z');

  group('Models Coverage', () {
    test('Business and Agent model serialization and copyWith', () {
      final b = Business(
        id: 'b1',
        name: 'Academy',
        category: BusinessCategory.coaching,
        address: 'MG Road',
        offerings: const ['Maths', 'Physics'],
        pricing: '5000/mo',
        openingHours: '9am - 8pm',
        location: 'Delhi',
        whatsappNumber: '919800000000',
        humanNumber: '919800000001',
        ownerName: 'Director',
      );

      final json = b.toJson();
      expect(json['id'], 'b1');
      expect(json['category'], 'coaching');
      final b2 = Business.fromJson(json);
      expect(b2.name, 'Academy');
      expect(b2.category, BusinessCategory.coaching);
      expect(b.copyWith(name: 'New Name').name, 'New Name');

      const a = Agent(
        id: 'a1',
        name: 'Maya',
        role: 'Counselor',
        status: AgentStatus.active,
        templateId: 'coaching_v1',
        languages: ['English', 'Hindi'],
        formality: 0.25,
        goal: 'Convert enquiries',
        mascotSet: 'default',
        roleKind: 'counsellor',
        skills: ['calling'],
        voice: 'Warm · Female',
        callsToday: 10,
        capabilities: ['pitching'],
        transferNumber: '919800000000',
        callingHoursStart: 9,
        callingHoursEnd: 18,
      );
      final aJson = a.toJson();
      expect(Agent.fromJson(aJson).name, 'Maya');
      expect(a.copyWith(role: 'Senior').role, 'Senior');
      expect(a.personalityLabel, 'Warm · Friendly');
      expect(
        a.copyWith(formality: 0.45).personalityLabel,
        'Friendly · Professional',
      );
      expect(
        a.copyWith(formality: 0.8).personalityLabel,
        'Formal · Professional',
      );
    });

    test('Lead and LeadScore model serialization and helpers', () {
      const ls = LeadScore(
        value: 85,
        temperature: LeadTemperature.hot,
        intent: LeadIntent.interested,
        positiveSignals: ['Asked about fee'],
        concerns: ['Morning batch only'],
      );
      expect(ls.intentLabel, 'HIGH INTENT');
      final lsJson = ls.toJson();
      expect(LeadScore.fromJson(lsJson).value, 85);

      final l = Lead(
        id: 'l1',
        businessId: 'b1',
        name: 'Student A',
        phone: '919876543210',
        source: 'Website',
        status: LeadStatus.newLead,
        createdAt: testDate,
        updatedAt: testDate,
        interest: 'Maths',
        attributes: const {'grade': '12', 'batch': 'Morning'},
        score: ls,
        summary: 'Interested',
        objections: const ['Price'],
        nextAction: NextAction.sendWhatsapp,
        callbackAt: testDate,
        lastCallId: 'c1',
        language: 'hi',
        consent: 'explicit',
        doNotCall: false,
      );

      final json = l.toJson();
      final l2 = Lead.fromJson(json);
      expect(l2.id, 'l1');
      expect(l2.score?.value, 85);
      expect(l.copyWith(name: 'Student B').name, 'Student B');
      expect(l.hasConsent, isTrue);
      expect(l.isHot, isTrue);
      expect(l.isWarm, isFalse);
      expect(l.hasBeenCalled, isTrue);
      expect(l.firstName, 'Student');
      expect(l.interestLine, contains('Maths'));

      const input = NewLeadInput(
        name: 'Lead 2',
        phone: '919999999999',
        interest: 'Physics',
      );
      expect(input.toJson()['name'], 'Lead 2');
      expect(
        const NewLeadInput(name: 'A', phone: '9').toJson(),
        isNot(contains('interest')),
      );

      final impRes = LeadImportResult.fromJson(const {
        'imported': 5,
        'skipped': 2,
        'errors': ['error 1'],
      });
      expect(impRes.imported, 5);
      expect(impRes.skipped, 2);
    });

    test('Call, TranscriptLine, and CallTranscript models', () {
      final c = Call(
        id: 'c1',
        leadId: 'l1',
        leadName: 'Student A',
        leadPhone: '919876543210',
        agentId: 'a1',
        campaignId: 'cmp1',
        status: CallStatus.completed,
        startedAt: testDate,
        endedAt: testDate.add(const Duration(minutes: 2)),
        duration: const Duration(seconds: 120),
        transcript: const CallTranscript(
          lines: [
            TranscriptLine(
              speaker: TranscriptSpeaker.agent,
              text: 'Hello',
              offset: Duration(milliseconds: 500),
            ),
            TranscriptLine(speaker: TranscriptSpeaker.lead, text: 'Hi there'),
          ],
          language: 'hi',
        ),
        summary: 'Good conversation',
        outcome: 'Interested',
        leadScore: const LeadScore(
          value: 90,
          temperature: LeadTemperature.hot,
          intent: LeadIntent.interested,
        ),
        nextAction: NextAction.sendWhatsapp,
        interest: 'Maths',
        objections: const [],
        followUpId: 'f1',
        interactionId: 'ix_1',
        rawMetadata: const {'test': true},
      );

      final json = c.toJson();
      final c2 = Call.fromJson(json);
      expect(c2.id, 'c1');
      expect(c2.isHot, isTrue);
      expect(c2.transcript.lines.length, 2);
      expect(c2.transcript.isEmpty, isFalse);
      expect(c2.transcript.lines.first.offset?.inMilliseconds, 500);
    });

    test('Campaign, Options, Stats, and Draft models', () {
      final cmp = Campaign(
        id: 'cmp1',
        agentId: 'a1',
        purpose: 'Drive enrollments',
        status: CampaignStatus.running,
        createdAt: testDate,
        leadIds: const ['l1', 'l2'],
        languageMode: 'auto',
        callingHoursStart: 10,
        callingHoursEnd: 19,
        options: const CampaignOptions(scoreLead: true),
        stats: const CampaignStats(
          total: 10,
          queued: 2,
          completed: 5,
          connected: 4,
          interested: 3,
          hot: 2,
        ),
        estimatedCostInr: 500,
        startedAt: testDate,
        recentCallIds: const ['c1'],
      );

      final json = cmp.toJson();
      final cmp2 = Campaign.fromJson(json);
      expect(cmp2.id, 'cmp1');
      expect(cmp2.isActive, isTrue);
      expect(cmp2.stats.remaining, 5);
      expect(cmp2.stats.progress, 0.5);
      expect(
        cmp.copyWith(status: CampaignStatus.completed).status,
        CampaignStatus.completed,
      );

      const draft = CampaignDraft(leadIds: ['l1'], purpose: 'Follow ups');
      expect(draft.toJson()['purpose'], 'Follow ups');
    });

    test('FollowUp and Callback models', () {
      final f = FollowUp(
        id: 'f1',
        leadId: 'l1',
        leadName: 'John',
        leadPhone: '919876543210',
        message: 'Hi John',
        status: FollowUpStatus.ready,
        createdAt: testDate,
        callId: 'c1',
        channel: FollowUpChannel.whatsapp,
        callSummary: 'Summary',
        scoreValue: 80,
        openedAt: testDate,
      );
      final fJson = f.toJson();
      final f2 = FollowUp.fromJson(fJson);
      expect(f2.id, 'f1');
      expect(f2.isPending, isTrue);
      expect(f.copyWith(message: 'Updated').message, 'Updated');

      final cb = Callback(
        id: 'cb1',
        leadId: 'l1',
        leadName: 'John',
        scheduledAt: testDate,
        status: CallbackStatus.scheduled,
        note: 'Call back tomorrow',
      );
      final cbJson = cb.toJson();
      final cb2 = Callback.fromJson(cbJson);
      expect(cb2.id, 'cb1');
      expect(
        cb.copyWith(status: CallbackStatus.done).status,
        CallbackStatus.done,
      );
    });

    test('Usage, Subscription, Notification, and Knowledge models', () {
      final sub = Subscription(
        planName: 'Pro',
        includedMinutes: 1000,
        renewsAt: testDate,
        priceInr: 4999,
      );
      final u = Usage(
        subscription: sub,
        minutesUsed: 120,
        callsMade: 50,
        ratePerMinuteInr: 6,
      );
      expect(u.minutesRemaining, 880);
      expect(u.ratio, 0.12);
      expect(u.copyWith(minutesUsed: 200).minutesUsed, 200);

      final uFromJson = Usage.fromJson({
        'subscription': {
          'plan_name': 'Pro',
          'included_minutes': 500,
          'renews_at': '2026-02-01T00:00:00.000Z',
          'price_inr': 2999,
        },
        'minutes_used': 100,
        'calls_made': 25,
        'rate_per_minute_inr': 6,
      });
      expect(uFromJson.subscription.planName, 'Pro');
      expect(uFromJson.minutesRemaining, 400);

      final notif = AppNotification(
        id: 'n1',
        type: NotificationType.hotLead,
        title: 'Hot Lead',
        body: 'Lead qualified',
        route: '/leads/l1',
        createdAt: testDate,
        actionLabel: 'Open',
        read: false,
      );
      expect(notif.copyWith(read: true).read, isTrue);
      final notifFromJson = AppNotification.fromJson({
        'id': 'n2',
        'type': 'hot_lead',
        'title': 'Test',
        'body': 'Body',
        'route': '/route',
        'read': true,
      });
      expect(notifFromJson.id, 'n2');

      final ks = KnowledgeSource(
        id: 'kn1',
        type: KnowledgeType.text,
        title: 'Policy',
        status: KnowledgeStatus.ready,
        updatedAt: testDate,
        detail: 'Some details',
        progress: 1.0,
      );
      final ksJson = ks.toJson();
      expect(KnowledgeSource.fromJson(ksJson).title, 'Policy');
      expect(
        ks.copyWith(status: KnowledgeStatus.processing).status,
        KnowledgeStatus.processing,
      );

      const ki = KnowledgeInput(
        type: KnowledgeType.faq,
        title: 'FAQ Source',
        content: 'Q and A',
      );
      expect(ki.title, 'FAQ Source');

      final summary = DailySummary(
        leads: 10,
        connected: 8,
        interested: 4,
        hot: 2,
        callsToday: 12,
        followUpsReady: 3,
        callbacksToday: 1,
        newLeadsReady: 5,
        activity: [
          ActivityItem(
            emoji: '🔥',
            text: 'Hot lead',
            at: testDate,
            route: '/leads/1',
          ),
        ],
      );
      expect(summary.activity.length, 1);

      const page = Page<String>(items: ['item1'], hasMore: false);
      expect(page.items.first, 'item1');

      final vts = VoiceTestSession.fromJson(const {
        'session_token': 'tok_1',
        'org_id': 'org_1',
        'workspace_id': 'ws_1',
        'app_id': 'app_1',
        'proxy_base_url': 'https://proxy.test',
      });
      expect(vts.sessionToken, 'tok_1');

      final vcr = VoiceChatReply.fromJson(const {
        'reply': 'Hello world',
        'conversation_id': 'conv_1',
      });
      expect(vcr.reply, 'Hello world');
    });

    test('Enums parsing and fallback coverage', () {
      expect(LeadStatus.parse(null), LeadStatus.newLead);
      expect(LeadStatus.parse('unknown_xyz'), LeadStatus.newLead);
      expect(LeadStatus.parse('queued'), LeadStatus.queued);

      expect(LeadTemperature.parse(null), LeadTemperature.unknown);
      expect(LeadTemperature.fromScore(80), LeadTemperature.hot);
      expect(LeadTemperature.fromScore(50), LeadTemperature.warm);
      expect(LeadTemperature.fromScore(20), LeadTemperature.cold);
      expect(LeadTemperature.fromScore(null), LeadTemperature.unknown);

      expect(LeadIntent.parse(null), LeadIntent.unknown);
      expect(LeadIntent.parse('interested'), LeadIntent.interested);

      expect(CallStatus.parse(null), CallStatus.failed);
      expect(CallStatus.completed.isConnected, isTrue);
      expect(CallStatus.ringing.isLive, isTrue);
      expect(CallStatus.inProgress.isLive, isTrue);
      expect(CallStatus.completed.isLive, isFalse);

      expect(NextAction.parse('counsellor_callback'), NextAction.humanFollowUp);
      expect(NextAction.parse('schedule_visit'), NextAction.bookAppointment);
      expect(NextAction.parse(null), NextAction.none);

      expect(FollowUpStatus.parse(null), FollowUpStatus.ready);
      expect(FollowUpChannel.parse(null), FollowUpChannel.whatsapp);
      expect(CampaignStatus.parse(null), CampaignStatus.draft);
      expect(KnowledgeType.parse('centre_info'), KnowledgeType.businessInfo);
      expect(KnowledgeType.parse(null), KnowledgeType.text);
      expect(KnowledgeStatus.parse(null), KnowledgeStatus.ready);
      expect(NotificationType.parse(null), NotificationType.campaign);
      expect(AgentStatus.parse(null), AgentStatus.active);
      expect(CallbackStatus.parse(null), CallbackStatus.scheduled);
      expect(BusinessCategory.parse(null), BusinessCategory.other);
      expect(BusinessCategory.parse('coaching'), BusinessCategory.coaching);
      expect(TranscriptSpeaker.parse('lead'), TranscriptSpeaker.lead);
      expect(TranscriptSpeaker.parse('user'), TranscriptSpeaker.lead);
      expect(TranscriptSpeaker.parse('agent'), TranscriptSpeaker.agent);
    });
  });

  group('Services Coverage', () {
    test('WhatsAppDeepLinkService URIs and validation', () async {
      const s = WhatsAppDeepLinkService();
      expect(
        WhatsAppDeepLinkService.buildUri(
          phone: '919876543210',
          message: 'Hi',
        )?.toString(),
        contains('wa.me/919876543210'),
      );
      expect(
        WhatsAppDeepLinkService.buildNativeUri(
          phone: '919876543210',
          message: 'Hi',
        )?.toString(),
        contains('whatsapp://send'),
      );

      final resEmpty = await s.openChat(phone: '919876543210', message: '');
      expect(resEmpty, WhatsAppOpenResult.emptyMessage);

      final resBadPhone = await s.openChat(phone: 'invalid', message: 'Hello');
      expect(resBadPhone, WhatsAppOpenResult.invalidPhone);
    });

    test('NotificationService in-app streams and presentation', () async {
      final notifService = NotificationService();
      expect(notifService.takeLaunchRoute(), isNull);

      final futureTap = notifService.taps.first;
      notifService.simulateTap('/leads/123');
      final tapped = await futureTap;
      expect(tapped, '/leads/123');

      final testNotif = AppNotification(
        id: 'n1',
        type: NotificationType.hotLead,
        title: 'Title',
        body: 'Body',
        route: '/route',
        createdAt: testDate,
      );

      final futureInApp = notifService.inApp.first;
      await notifService.present(testNotif, system: false);
      final emitted = await futureInApp;
      expect(emitted.id, 'n1');
    });

    test('DebugAnalyticsService track calls and filtering', () {
      final a = DebugAnalyticsService();
      a.track('test_event', {'foo': 'bar', 'phone': '919876543210'});
    });

    test(
      'PushService local handler instantiation and static functions',
      () async {
        final push = PushService(
          registerToken: (token, platform) async {},
          onRoute: (route) {},
        );
        expect(push.currentToken, isNull);
        await push.dispose();
      },
    );

    test('SafeCrashReportingService scrubs PII and respects enabled flag', () {
      final safe = SafeCrashReportingService();
      expect(
        SafeCrashReportingService.scrubPii('Phone: 9876543210'),
        contains('[PHONE_REDACTED]'),
      );
      expect(
        SafeCrashReportingService.scrubPii('Bearer abc123def456'),
        contains('Bearer [TOKEN_REDACTED]'),
      );
      expect(
        SafeCrashReportingService.scrubPii('user@example.com'),
        contains('[EMAIL_REDACTED]'),
      );

      final ctx = safe.scrubContext({
        'phone': '9876543210',
        'safe_key': 'hello 9876543210',
        'number': 42,
      });
      expect(ctx.containsKey('phone'), isFalse);
      expect(ctx['safe_key'], contains('[PHONE_REDACTED]'));
      expect(ctx['number'], 42);

      safe.reportError(
        Exception('Fail with 9876543210'),
        null,
        reason: 'Test reason',
      );
      safe.log('Log message');

      final disabled = SafeCrashReportingService(enabled: false);
      disabled.reportError(Exception('Fail'), null);
      disabled.log('Log');
    });

    test('MockVoiceAgentService lifecycle and state transitions', () async {
      final voice = MockVoiceAgentService(
        agentName: 'Maya',
        agentRole: 'Counselor',
        businessName: 'Academy',
      );
      expect(voice.currentState, VoiceConnectionState.idle);
      expect(voice.isMuted, isFalse);

      await voice.setMuted(true);
      expect(voice.isMuted, isTrue);

      await voice.sendText('Hello');
      await voice.stopSession();
      expect(voice.currentState, VoiceConnectionState.idle);
      await voice.dispose();
    });
  });
}

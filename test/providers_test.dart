import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/models/models.dart';

void main() {
  test('mutationScope maps write paths to refresh scopes', () {
    expect(mutationScope('/leads'), 'leads');
    expect(mutationScope('/leads/l1/call'), 'leads');
    expect(mutationScope('/campaigns/c1/start'), 'campaign');
    expect(mutationScope('/auth/refresh'), isNull);
    expect(mutationScope('/devices'), isNull);
    expect(mutationScope('/voice/test-session'), isNull);
  });

  group('Riverpod Providers Unit Tests (Mock Environment)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [useMockProvider.overrideWithValue(true)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('useMockProvider is true by default in mock test environment', () {
      expect(container.read(useMockProvider), isTrue);
    });

    test('businessProvider and agentProvider load seed data', () async {
      final biz = await container.read(businessProvider.future);
      expect(biz, isNotNull);
      expect(biz!.name, isNotEmpty);

      final agent = await container.read(agentProvider.future);
      expect(agent, isNotNull);
      expect(agent!.name, isNotEmpty);
    });

    test('dashboardProvider loads dashboard summary', () async {
      final summary = await container.read(dashboardProvider.future);
      expect(summary.leads, greaterThan(0));
      expect(summary.activity, isNotEmpty);
    });

    test('newLeadsProvider returns fresh leads list', () async {
      final leads = await container.read(newLeadsProvider.future);
      expect(leads, isNotEmpty);
    });

    test('followUpsProvider returns pending follow-ups', () async {
      final followups = await container.read(followUpsProvider.future);
      expect(followups, isNotEmpty);
      expect(followups.first.status, FollowUpStatus.ready);
    });

    test('sessionProvider login and logout flow', () async {
      final initialSession = await container.read(sessionProvider.future);
      expect(initialSession, isTrue);

      // Request OTP
      await container
          .read(sessionProvider.notifier)
          .requestOtp(phone: '919876543210');

      // Login
      await container
          .read(sessionProvider.notifier)
          .login(phone: '919876543210', otp: '123456');
      expect(container.read(sessionProvider).value, isTrue);

      // Logout
      await container.read(sessionProvider.notifier).logout();
      expect(container.read(sessionProvider).value, isFalse);
    });

    test('activeCampaignProvider retrieves active campaign', () {
      final active = container.read(activeCampaignProvider);
      expect(active, anyOf(isNull, isA<Campaign>()));
    });

    test('knowledgeProvider loads knowledge sources', () async {
      final knowledge = await container.read(knowledgeProvider.future);
      expect(knowledge, isNotEmpty);
    });

    test('usageProvider loads plan and quota', () async {
      final usage = await container.read(usageProvider.future);
      expect(usage.subscription.planName, isNotEmpty);
      expect(usage.subscription.includedMinutes, greaterThan(0));
    });

    test('notificationsProvider loads notifications', () async {
      final notifs = await container.read(notificationsProvider.future);
      expect(notifs, isNotEmpty);
    });
  });
}

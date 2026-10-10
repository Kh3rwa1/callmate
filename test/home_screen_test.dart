import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/campaign/campaign_screens.dart';
import 'package:callpilot/features/home/home_widgets.dart';
import 'package:callpilot/core/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Dashboard that fails once, then delegates to a fixed summary.
class _FlakyDashboard implements DashboardRepository {
  int calls = 0;
  @override
  Future<DailySummary> today() async {
    calls++;
    if (calls == 1) throw StateError('connection reset');
    return const DailySummary(
      leads: 3,
      connected: 1,
      interested: 1,
      hot: 0,
      callsToday: 2,
      followUpsReady: 0,
      callbacksToday: 0,
      newLeadsReady: 0,
    );
  }

  @override
  Future<ResultsSummary> results(ResultsRange range) async =>
      ResultsSummary(range: range, current: const PeriodResults());
}

bool _chipSelected(String label) =>
    (find.widgetWithText(AppFilterChip, label).evaluate().single.widget
            as AppFilterChip)
        .selected;

void main() {
  group('HomeScreen', () {
    appTest('shows business, agent card and today\'s metrics', (h) async {
      final b = h.backend;
      expect(find.textContaining(b.business.name), findsOneWidget);
      expect(find.text(b.agent.name), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text("Today's results"), findsOneWidget);

      final hot = b.leads.values.where((l) => l.isHot).length;
      expect(find.text('$hot ready to buy'), findsOneWidget);

      final pending = b.followUps.values.where((f) => f.isPending).length;
      expect(find.text('$pending messages ready'), findsOneWidget);

      final newLeads = b.leads.values
          .where((l) => l.status == LeadStatus.newLead)
          .length;
      expect(find.text('Call $newLeads New Customers'), findsOneWidget);

      final unread = b.notifications.where((n) => !n.read).length;
      expect(
        find.bySemanticsLabel('$unread new notifications'),
        findsOneWidget,
      );
    });

    appTest('hot leads action opens leads filtered to hot', (h) async {
      final hotCount = h.backend.leads.values.where((l) => l.isHot).length;
      await h.tapText('$hotCount ready to buy');
      expect(h.location, '/leads');
      expect(_chipSelected('Wants to buy'), isTrue);
    });

    appTest('metric tiles deep link into filtered lists', (h) async {
      await h.tapText('Connected');
      expect(h.location, '/calls');
      expect(_chipSelected('Connected'), isTrue);

      await h.go('/home');
      await h.tapText('Interested');
      expect(h.location, '/leads');
      expect(_chipSelected('Thinking'), isTrue);
    });

    appTest('agent card, notifications and follow-ups navigate', (h) async {
      await h.tap(find.byIcon(Icons.notifications_none_rounded));
      expect(h.location, '/notifications');

      await h.go('/home');
      await h.tap(find.byType(HomeAgentCard));
      expect(h.location, '/agent');

      await h.go('/home');
      final pending = h.backend.followUps.values
          .where((f) => f.isPending)
          .length;
      await h.tapText('$pending messages ready');
      expect(h.location, '/followups');
    });

    appTest('callbacks card and activity rows navigate', (h) async {
      final n = h.container.read(dashboardProvider).value!.callbacksToday;
      expect(n, greaterThan(0));
      await h.tapText(n == 1 ? '1 call back' : '$n call backs');
      expect(h.location, '/callbacks');

      await h.go('/home');
      final activity = h.backend.activity.firstWhere(
        (a) => a.route == '/calls',
      );
      await h.tapText(activity.text);
      expect(h.location, '/calls');
    });

    appTest('new leads CTA opens campaign setup', (h) async {
      await h.tap(find.textContaining('New Customers').first);
      expect(h.location, '/campaign/new');
      expect(find.byType(CampaignSetupScreen), findsOneWidget);
    });

    appTest('live campaign banner appears and opens progress', (h) async {
      final b = h.backend;
      final ids = b.leads.values
          .where((l) => l.status == LeadStatus.newLead)
          .take(2)
          .map((l) => l.id)
          .toList();
      // Mark the campaign running directly (no dialer timer) and publish it
      // the way the backend progress events do.
      final c = b
          .createCampaign(CampaignDraft(leadIds: ids, purpose: 'Admissions'))
          .copyWith(status: CampaignStatus.running);
      b.campaigns[c.id] = c;
      h.container.read(activeCampaignProvider.notifier).set(c);
      await h.settle(2);

      expect(
        find.text('${b.agent.name} is calling your customers…'),
        findsOneWidget,
      );
      await h.tap(find.text('${b.agent.name} is calling your customers…'));
      expect(h.location, '/campaigns/${c.id}');
      expect(find.byType(CampaignProgressScreen), findsOneWidget);
    });

    appTest('without hot leads it suggests calling new leads', (h) async {
      h.backend.leads.removeWhere((_, l) => l.isHot);
      h.backend.emitChanged('leads');
      await h.settle();
      expect(find.text('No one ready to buy yet'), findsOneWidget);
      await h.tapText('Call new customers');
      expect(h.location, '/campaign/new');
    });

    appTest(
      'dashboard error shows retry which reloads',
      (h) async {
        expect(find.text('Try again'), findsOneWidget);
        expect(
          find.text('No connection. Check your internet and try again.'),
          findsOneWidget,
        );
        await h.tapText('Try again');
        expect(find.text('All caught up'), findsOneWidget);
        expect(find.text('No one ready to buy yet'), findsOneWidget);
        // The summary has no activity yet.
        expect(find.text('No calls yet'), findsOneWidget);
      },
      overrides: () => [
        dashboardRepoProvider.overrideWithValue(_FlakyDashboard()),
      ],
    );
  });

  testWidgets('HomeSkeleton renders placeholder blocks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HomeSkeleton())),
      ),
    );
    expect(find.byType(HomeSkeleton), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}

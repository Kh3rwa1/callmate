import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/widgets/state_views.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/campaign/campaign_progress_widgets.dart';
import 'package:callpilot/features/campaign/campaign_screens.dart';
import 'package:callpilot/features/campaign/campaign_setup_widgets.dart';
import 'package:callpilot/features/campaign/campaign_widgets.dart';
import 'package:callpilot/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

int _newLeadCount(MockBackend b) =>
    b.leads.values.where((l) => l.status == LeadStatus.newLead).length;

bool _checked(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(CheckboxListTile),
      ),
    )
    .value!;

/// Scrolls the screen's main list until [finder] is built and visible.
Future<void> _scrollTo(AppHarness h, Finder finder) async {
  await h.tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await h.tester.pump();
}

/// Swipes away the in-app notification banner (it overlays the app bar).
Future<void> _dismissBanner(AppHarness h) async {
  final banner = find.byType(InAppNotificationBanner);
  if (banner.evaluate().isEmpty) return;
  await h.tester.fling(banner, const Offset(0, -300), 1000);
  await h.settle(4);
}

/// Opens the confirmation sheet from the setup screen and confirms it.
Future<void> _startCampaign(AppHarness h) async {
  await h.tapText('Start Calling');
  final attest = find.text('I confirm these contacts asked to be contacted');
  if (attest.evaluate().isNotEmpty) await h.tap(attest);
  expect(find.textContaining('Start calling'), findsOneWidget);
  await h.tapText('Yes, start calling');
  // create (280 ms) + start (500 ms) of mock latency.
  await h.settle(12);
}

void main() {
  group('CampaignSetupScreen', () {
    appTest('summarises the new leads and the agent', (h) async {
      final count = _newLeadCount(h.backend);
      expect(count, greaterThan(0));
      expect(find.byType(CampaignSetupScreen), findsOneWidget);
      expect(find.text('$count'), findsWidgets);
      expect(find.text('customers ready'), findsOneWidget);
      expect(find.text(h.backend.agent.name), findsOneWidget);
      expect(find.byType(CampaignSummaryRow), findsNWidgets(4));
      expect(find.text('Auto detect'), findsOneWidget);
      expect(find.byType(CampaignChecklistItem), findsNWidgets(4));
    }, location: '/campaign/new');

    appTest('checklist items toggle their options', (h) async {
      for (final label in [
        'Score the customer',
        'Write a WhatsApp message',
        'Suggest a call back',
        'Tell me who is ready to buy',
      ]) {
        final before = _checked(h.tester, label);
        await h.tapText(label);
        expect(_checked(h.tester, label), !before, reason: label);
      }
    }, location: '/campaign/new');

    appTest('dragging the hours slider updates calling hours', (h) async {
      final row = find.ancestor(
        of: find.text('Calling hours'),
        matching: find.byType(CampaignSummaryRow),
      );
      String hours() => h.tester.widget<CampaignSummaryRow>(row).value;
      final before = hours();
      final slider = find.byType(RangeSlider);
      await h.tester.ensureVisible(slider);
      final rect = h.tester.getRect(slider);
      // Drag the end thumb (right side) further right.
      final endThumbX =
          rect.left + 24 + (rect.width - 48) * ((19 - 8) / (21 - 8));
      await h.tester.dragFrom(
        Offset(endThumbX, rect.center.dy),
        Offset(rect.width / 6, 0),
      );
      await h.settle(2);
      expect(hours(), isNot(before));
    }, location: '/campaign/new');

    appTest(
      'without consent the sheet counts only callable leads',
      (h) async {
        await h.tapText('Start Calling');
        final attest = find.text(
          'I confirm these contacts asked to be contacted',
        );
        if (attest.evaluate().isEmpty) return; // seed has consented leads only
        final unknown = h.backend.leads.values
            .where(
              (l) => l.status == LeadStatus.newLead && l.consent == 'unknown',
            )
            .length;
        expect(find.textContaining('will be skipped'), findsOneWidget);
        expect(
          find.textContaining('Start calling $unknown customers'),
          findsNothing,
        );
        await h.tap(attest);
        expect(find.textContaining('will be skipped'), findsNothing);
      },
      location: '/campaign/new',
    );

    appTest('"Not now" cancels without creating a campaign', (h) async {
      await h.tapText('Start Calling');
      await h.tapText('Not now');
      expect(h.backend.campaigns, isEmpty);
      expect(find.byType(CampaignSetupScreen), findsOneWidget);
    }, location: '/campaign/new');

    appTest(
      'starting creates a running campaign and opens its progress',
      (h) async {
        final count = _newLeadCount(h.backend);
        // Turn off one option to check it is carried into the campaign.
        await h.tapText('Suggest a call back');
        await h.tapText('Start Calling');
        // Leads without recorded consent trigger the attestation checkbox.
        final attest = find.text(
          'I confirm these contacts asked to be contacted',
        );
        if (attest.evaluate().isNotEmpty) {
          await h.tap(attest);
        }
        await h.tapText('Yes, start calling');
        await h.settle(12);

        expect(h.backend.campaigns, hasLength(1));
        final c = h.backend.campaigns.values.single;
        expect(c.status, CampaignStatus.running);
        expect(c.leadIds, hasLength(count));
        expect(c.options.recommendCallback, isFalse);
        expect(h.location, '/campaigns/${c.id}');
        expect(find.byType(CampaignProgressScreen), findsOneWidget);
        expect(find.text('${h.backend.agent.name} is calling'), findsOneWidget);
      },
      location: '/campaign/new',
    );

    appTest(
      'shows an empty state when there are no new leads',
      (h) async {
        expect(find.text('No new customers to call'), findsOneWidget);
        await h.tapText('Add customers');
        expect(h.location, '/leads/import');
      },
      location: '/campaign/new',
      backend: () {
        final b = MockBackend();
        b.leads.updateAll((_, l) => l.copyWith(status: LeadStatus.called));
        return b;
      },
    );
  });

  group('CampaignProgressScreen', () {
    appTest('progress advances as calls complete, then stop', (h) async {
      await _startCampaign(h);
      final id = h.backend.campaigns.keys.single;

      // Each mock tick (1.4 s) dials or finishes a call.
      for (var i = 0; i < 6; i++) {
        await h.tester.pump(const Duration(milliseconds: 1400));
      }
      await h.settle(6);
      final stats = h.backend.campaigns[id]!.stats;
      expect(stats.completed, greaterThan(0));
      await _scrollTo(h, find.text('Latest results'));
      expect(find.text('Latest results'), findsOneWidget);
      expect(find.byType(CampaignRecentCallTile), findsWidgets);
      expect(find.byType(CampaignStatTile), findsNWidgets(3));

      // Stop: first "Keep going", then actually stop.
      await _dismissBanner(h);
      await h.tapText('Stop');
      expect(find.text('Pause calling?'), findsOneWidget);
      await h.tapText('Keep going');
      expect(h.backend.campaigns[id]!.status, CampaignStatus.running);

      await _dismissBanner(h);
      await h.tapText('Stop');
      await h.tap(find.text('Stop').last);
      expect(h.backend.campaigns[id]!.status, CampaignStatus.stopped);
      expect(find.text('Calling stopped'), findsOneWidget);
      expect(find.textContaining('customers called'), findsOneWidget);

      await _scrollTo(h, find.text('Review messages'));
      await h.tapText('Review messages');
      expect(h.location, '/followups');
    }, location: '/campaign/new');

    appTest('completes after every lead was called', (h) async {
      await _startCampaign(h);
      final id = h.backend.campaigns.keys.single;
      final total = h.backend.campaigns[id]!.leadIds.length;
      await h.tester.pump(Duration(milliseconds: 1400 * (total * 2 + 3)));
      await h.settle(6);

      final c = h.backend.campaigns[id]!;
      expect(c.status, CampaignStatus.completed);
      expect(c.stats.completed, total);
      expect(find.textContaining('finished calling'), findsOneWidget);

      await _scrollTo(h, find.text('See ready-to-buy customers'));
      await h.tapText('See ready-to-buy customers');
      expect(h.location, '/leads');
    }, location: '/campaign/new');

    appTest('recent call tiles open the call', (h) async {
      await _startCampaign(h);
      for (var i = 0; i < 4; i++) {
        await h.tester.pump(const Duration(milliseconds: 1400));
      }
      await h.settle(6);
      await _scrollTo(h, find.byType(CampaignRecentCallTile).first);
      final tile = find.byType(CampaignRecentCallTile).first;
      final callId = h.tester.widget<CampaignRecentCallTile>(tile).callId;
      await h.tap(tile);
      expect(h.location, startsWith('/calls/$callId'));
    }, location: '/campaign/new');

    appTest('loads a campaign that is not the live one', (h) async {
      final c = h.backend.createCampaign(
        CampaignDraft(
          leadIds: h.backend.leads.keys.take(2).toList(),
          purpose: 'Test',
          callingHoursStart: 10,
          callingHoursEnd: 18,
          options: const CampaignOptions(),
        ),
      );
      await h.push('/campaigns/${c.id}');
      expect(find.byType(CampaignProgressScreen), findsOneWidget);
      expect(find.text('Calling stopped'), findsOneWidget);
      expect(find.text('0 of 2 customers called'), findsOneWidget);
    });

    appTest('unknown campaign shows an error', (h) async {
      await h.push('/campaigns/does_not_exist');
      expect(find.byType(ErrorState), findsOneWidget);
    });
  });

  group('Campaign widgets', () {
    appTest('CallNewLeadsButton on home opens campaign setup', (h) async {
      final button = find.byType(CallNewLeadsButton);
      expect(button, findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.textContaining('New Customers'),
        ),
        findsOneWidget,
      );
      await h.tap(button);
      expect(h.location, '/campaign/new');
    });

    appTest('CampaignLiveBanner on home links to the live campaign', (h) async {
      // A running campaign without the mock dialer timer, so no data
      // changes race with the navigation.
      final draft = h.backend.createCampaign(
        CampaignDraft(
          leadIds: h.backend.leads.keys.take(3).toList(),
          purpose: 'Test',
          callingHoursStart: 10,
          callingHoursEnd: 18,
          options: const CampaignOptions(),
        ),
      );
      final running = draft.copyWith(status: CampaignStatus.running);
      h.backend.campaigns[draft.id] = running;
      h.container.read(activeCampaignProvider.notifier).set(running);
      final id = running.id;
      await h.settle();
      final banner = find.byType(CampaignLiveBanner);
      expect(banner, findsOneWidget);
      expect(find.textContaining('is calling your customers…'), findsOneWidget);
      expect(find.textContaining('0 of 3 done'), findsOneWidget);
      // Tap in place: scrolling it into view would tuck it under the
      // pinned header.
      await h.tester.tap(banner);
      await h.settle();
      expect(h.location, '/campaigns/$id');
    });
  });
}

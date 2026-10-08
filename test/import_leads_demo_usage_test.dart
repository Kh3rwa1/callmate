import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/campaign/campaign_screens.dart';
import 'package:callpilot/features/demo/demo_screen.dart';
import 'package:callpilot/features/followups/followup_detail_screen.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/leads/import_leads_screen.dart';
import 'package:callpilot/features/notifications/notifications_screen.dart';
import 'package:callpilot/features/shell/app_shell.dart';
import 'package:callpilot/features/splash/splash_screen.dart';
import 'package:callpilot/features/usage/usage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

Future<void> _scrollTo(AppHarness h, Finder finder) async {
  await h.tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await h.tester.pump();
}

Future<void> _tapListItem(AppHarness h, Finder finder) async {
  await _scrollTo(h, finder);
  await h.tap(finder);
}

Finder _hint(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

Finder _navItem(String label) =>
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label));

void main() {
  group('ImportLeadsScreen', () {
    appTest('sample CSV previews valid rows and skips bad ones', (h) async {
      expect(find.byType(ImportLeadsScreen), findsOneWidget);
      await h.tapText('Try with sample leads');
      // 6 data rows, one with an invalid phone number.
      expect(find.text('5 ready'), findsOneWidget);
      expect(find.text('1 skipped'), findsOneWidget);
      expect(find.text('Riddhi Sen'), findsOneWidget);
      expect(find.textContaining('⚠️'), findsOneWidget);
      expect(find.text('Import 5 leads'), findsOneWidget);
    }, location: '/leads/import');

    appTest('importing the sample adds leads and offers to call', (h) async {
      final before = h.backend.leads.length;
      await h.tapText('Try with sample leads');
      await _tapListItem(h, find.text('Import 5 leads'));
      expect(h.backend.leads.length, before + 5);
      expect(
        h.backend.leads.values.where((l) => l.name == 'Karan Mehta'),
        hasLength(1),
      );
      expect(find.text('5 leads imported'), findsOneWidget);

      await h.tapText('Call them now');
      expect(h.location, '/campaign/new');
      expect(find.byType(CampaignSetupScreen), findsOneWidget);
    }, location: '/leads/import');

    appTest('"Later" closes the import result', (h) async {
      await h.push('/leads/import');
      await h.tapText('Try with sample leads');
      await _tapListItem(h, find.text('Import 5 leads'));
      await h.tapText('Later');
      expect(find.text('5 leads imported'), findsNothing);
      expect(find.byType(ImportLeadsScreen), findsNothing);
      expect(h.location, '/home');
    });

    appTest('a single lead is validated, then added', (h) async {
      final before = h.backend.leads.length;
      await _tapListItem(h, find.text('Add lead'));
      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
      expect(h.backend.leads.length, before);

      await h.tester.enterText(_hint('Customer name'), 'Zoya Testlead');
      await h.tester.enterText(_hint('Mobile number'), '98765 43210');
      await _tapListItem(h, find.text('Add lead'));

      expect(h.backend.leads.length, before + 1);
      expect(
        h.backend.leads.values.where((l) => l.name == 'Zoya Testlead'),
        hasLength(1),
      );
      expect(find.textContaining('Lead added ✓'), findsOneWidget);
      // Form is cleared for the next lead.
      expect(
        h.tester.widget<TextField>(_hint('Customer name')).controller!.text,
        isEmpty,
      );
    }, location: '/leads/import');
  });

  group('DemoScreen', () {
    appTest('simulate hot lead runs a call and opens its result', (h) async {
      expect(find.byType(DemoScreen), findsOneWidget);
      final calls = h.backend.calls.length;
      await h.tapText('Simulate hot lead');
      expect(h.backend.calls.length, calls + 1);
      final call = h.backend.calls.first;
      expect(call.leadScore?.temperature, LeadTemperature.hot);
      expect(h.location, '/calls/${call.id}/result');
      expect(find.byType(CallResultScreen), findsOneWidget);
    }, location: '/demo');

    appTest('simulate call completed drafts a warm follow-up', (h) async {
      await h.tapText('Simulate call completed');
      final call = h.backend.calls.first;
      expect(call.leadScore?.temperature, LeadTemperature.warm);
      expect(h.location, '/calls/${call.id}/result');
    }, location: '/demo');

    appTest('simulate WhatsApp follow-up opens the draft', (h) async {
      await h.tapText('Simulate WhatsApp follow-up');
      final call = h.backend.calls.first;
      expect(call.followUpId, isNotNull);
      expect(h.location, '/followups/${call.followUpId}');
      expect(find.byType(FollowUpDetailScreen), findsOneWidget);
    }, location: '/demo');

    appTest('simulate campaign opens campaign setup', (h) async {
      await h.tapText('Simulate campaign progress');
      expect(h.location, '/campaign/new');
    }, location: '/demo');

    appTest('notification tiles show a deep-linking banner', (h) async {
      final count = h.backend.notifications.length;
      await _tapListItem(h, find.text('Follow-up ready notification'));
      expect(h.backend.notifications.length, count + 1);
      final n = h.backend.notifications.first;
      expect(n.type, NotificationType.followUpReady);
      final banner = find.byType(InAppNotificationBanner);
      expect(banner, findsOneWidget);
      expect(find.text('💬 Follow-up ready'), findsOneWidget);

      await h.tap(
        find.descendant(of: banner, matching: find.byType(FilledButton)),
      );
      expect(h.location, n.route);
      expect(find.byType(InAppNotificationBanner), findsNothing);
    }, location: '/demo');

    appTest('hot lead and callback notifications are recorded', (h) async {
      await _tapListItem(h, find.text('Hot lead notification'));
      expect(h.backend.notifications.first.type, NotificationType.hotLead);
      expect(find.text('🔥 Hot lead detected'), findsOneWidget);
      await _tapListItem(h, find.text('Callback notification'));
      expect(h.backend.notifications.first.type, NotificationType.callback);
      expect(find.text('📅 Callback requested'), findsOneWidget);
    }, location: '/demo');

    appTest('replay onboarding resets prefs and restarts the flow', (h) async {
      expect(h.prefs.onboarded, isTrue);
      await _tapListItem(h, find.text('Replay onboarding'));
      expect(h.prefs.onboarded, isFalse);
      expect(h.location, '/onboarding');
    }, location: '/demo');
  });

  group('UsageScreen', () {
    appTest('shows plan, minutes and upgrade prompt', (h) async {
      final u = h.backend.usage;
      expect(find.byType(UsageScreen), findsOneWidget);
      expect(find.text(u.subscription.planName.toUpperCase()), findsOneWidget);
      expect(find.text('Calls made'), findsOneWidget);
      expect(find.text('Renews on'), findsOneWidget);
      expect(find.text('used'), findsOneWidget);
      expect(find.text('remaining'), findsOneWidget);

      await _tapListItem(h, find.text('Upgrade'));
      expect(
        find.text('Our team will reach out on WhatsApp to upgrade your plan.'),
        findsOneWidget,
      );
    }, location: '/usage');
  });

  group('SplashScreen', () {
    appTest('continues to home when onboarded', (h) async {
      h.router.go('/splash');
      await h.tester.pump(const Duration(milliseconds: 50));
      await h.tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SplashScreen), findsOneWidget);
      await h.tester.pump(const Duration(milliseconds: 1500));
      await h.settle(4);
      expect(h.location, '/home');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    appTest('continues to onboarding when not onboarded', (h) async {
      h.router.go('/splash');
      await h.tester.pump(const Duration(milliseconds: 50));
      await h.tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SplashScreen), findsOneWidget);
      await h.tester.pump(const Duration(milliseconds: 1500));
      await h.settle(4);
      expect(h.location, '/onboarding');
    }, onboarded: false);
  });

  group('AppShell', () {
    appTest('bottom navigation switches tabs', (h) async {
      for (final (label, path) in [
        ('Leads', '/leads'),
        ('Calls', '/calls'),
        ('Follow-ups', '/followups'),
        ('Agent', '/agent'),
        ('Home', '/home'),
      ]) {
        await h.tap(_navItem(label));
        expect(h.location, path, reason: label);
      }
    });

    appTest('re-selecting the current tab resets it', (h) async {
      await h.go('/leads?filter=hot');
      expect(h.router.state.uri.queryParameters['filter'], 'hot');
      await h.tap(_navItem('Leads'));
      expect(h.location, '/leads');
      expect(h.router.state.uri.queryParameters, isEmpty);
    });

    appTest('follow-ups tab shows the pending badge', (h) async {
      final pending = h.backend.followUps.values
          .where((f) => f.isPending)
          .length;
      expect(pending, greaterThan(0));
      final badge = find.descendant(
        of: find.byType(AppNavBar),
        matching: find.byType(Badge),
      );
      expect(badge, findsOneWidget);
      expect(h.tester.widget<Badge>(badge).isLabelVisible, isTrue);
    });
  });
}

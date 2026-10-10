import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/callbacks/callbacks_screen.dart';
import 'package:callpilot/features/leads/lead_detail_screen.dart';
import 'package:callpilot/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _FailingCallbacks extends MockCallbackRepository {
  _FailingCallbacks(super.b);
  @override
  Future<Callback> schedule({
    required String leadId,
    required DateTime at,
    String? note,
  }) async => throw StateError('network down');
}

List<Callback> _upcoming(MockBackend b) =>
    b.callbacks.values
        .where((c) => c.status == CallbackStatus.scheduled)
        .toList()
      ..sort((x, y) => x.scheduledAt.compareTo(y.scheduledAt));

void main() {
  group('CallbacksScreen', () {
    appTest('lists upcoming callbacks and opens the lead', (h) async {
      await h.push('/callbacks');
      final first = _upcoming(h.backend).first;
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text(first.leadName), findsWidgets);

      await h.tap(find.text(first.leadName).first);
      expect(h.location, '/leads/${first.leadId}');
      expect(find.byType(LeadDetailScreen), findsOneWidget);

      h.router.pop();
      await h.settle();
      await h.tester.scrollUntilVisible(
        find.text('Swipe left to mark done'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
    });

    appTest('swiping left marks a callback done', (h) async {
      await h.push('/callbacks');
      final first = _upcoming(h.backend).first;
      await h.tester.drag(
        find.text(first.leadName).first,
        const Offset(-600, 0),
      );
      await h.settle();
      expect(h.backend.callbacks[first.id]!.status, CallbackStatus.done);
      expect(
        find.text(
          "Marked ${first.leadName.split(' ').first}'s call back as done ✓",
        ),
        findsOneWidget,
      );
      await h.tester.scrollUntilVisible(
        find.text('Done'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(first.leadName), findsWidgets);
    });

    appTest('no callbacks shows an empty state', (h) async {
      await h.push('/callbacks');
      expect(find.byType(CallbacksScreen), findsOneWidget);
      expect(find.text('No call backs yet'), findsOneWidget);
    }, backend: () => MockBackend()..callbacks.clear());
  });

  group('Callback sheet', () {
    Lead newLead(MockBackend b) =>
        b.leads.values.firstWhere((l) => l.status == LeadStatus.newLead);

    appTest('suggests the AI-proposed time first', (h) async {
      final lead = newLead(h.backend);
      final suggested = DateTime.now().add(const Duration(days: 2));
      h.backend.leads[lead.id] = lead.copyWith(callbackAt: suggested);
      await h.push('/leads/${lead.id}');
      await h.tap(find.byTooltip('Call back'));
      expect(find.text('Suggested by ${h.backend.agent.name}'), findsOneWidget);
      await h.tap(find.widgetWithText(FilledButton, 'Schedule Call Back'));
      final cb = _upcoming(h.backend).singleWhere((c) => c.leadId == lead.id);
      expect(cb.scheduledAt, suggested);
    });

    appTest('custom date and time can be picked', (h) async {
      final lead = newLead(h.backend);
      await h.push('/leads/${lead.id}');
      await h.tap(find.byTooltip('Call back'));
      await h.tapText('Pick date & time');
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await h.tap(find.byTooltip('Next month'));
      await h.tapText('15');
      await h.tapText('OK');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await h.tapText('OK');
      // A custom slot is now selected instead of a preset.
      expect(find.text('Choose any slot'), findsNothing);

      await h.tap(find.widgetWithText(FilledButton, 'Schedule Call Back'));
      final cb = _upcoming(h.backend).singleWhere((c) => c.leadId == lead.id);
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      expect(cb.scheduledAt.day, 15);
      expect(cb.scheduledAt.month, nextMonth.month);
    });

    appTest(
      'failure keeps the sheet open and reports the error',
      (h) async {
        final lead = newLead(h.backend);
        await h.push('/leads/${lead.id}');
        await h.tap(find.byTooltip('Call back'));
        await h.tap(find.widgetWithText(FilledButton, 'Schedule Call Back'));
        expect(find.text('Schedule call back'), findsOneWidget);
        expect(
          find.text('No connection. Check your internet and try again.'),
          findsOneWidget,
        );
        expect(_upcoming(h.backend).where((c) => c.leadId == lead.id), isEmpty);
      },
      overrides: () => [
        callbackRepoProvider.overrideWith(
          (ref) => _FailingCallbacks(ref.watch(mockBackendProvider)),
        ),
      ],
    );
  });

  group('NotificationsScreen', () {
    appTest('lists notifications and opens their route', (h) async {
      await h.push('/notifications');
      final n1 = h.backend.notifications.firstWhere((n) => n.id == 'n_1');
      expect(n1.read, isFalse);
      expect(find.text('Customer ready to buy'), findsOneWidget);
      expect(find.text(n1.body), findsOneWidget);

      await h.tapText('Customer ready to buy');
      expect(h.location, n1.route);
      expect(
        h.backend.notifications.firstWhere((n) => n.id == 'n_1').read,
        isTrue,
      );
    });

    appTest('empty list says all caught up', (h) async {
      await h.push('/notifications');
      expect(find.text('All caught up'), findsOneWidget);
    }, backend: () => MockBackend()..notifications.clear());
  });

  group('In-app notification banner', () {
    appTest('backend notification shows a banner that deep links', (h) async {
      final n = h.backend.simulateNotification(NotificationType.callback);
      await h.settle(2);
      expect(find.byType(InAppNotificationBanner), findsOneWidget);
      expect(find.text('Call back requested'), findsOneWidget);

      await h.tap(find.widgetWithText(FilledButton, n.actionLabel));
      expect(h.location, n.route);
      expect(find.byType(InAppNotificationBanner), findsNothing);
    });

    appTest('banner hides itself after a few seconds', (h) async {
      h.backend.simulateNotification(NotificationType.campaign);
      await h.settle(2);
      expect(find.byType(InAppNotificationBanner), findsOneWidget);
      await h.tester.pump(const Duration(seconds: 7));
      await h.settle(3);
      expect(find.byType(InAppNotificationBanner), findsNothing);
    });

    appTest('banner can be swiped away', (h) async {
      h.backend.simulateNotification(NotificationType.followUpReady);
      await h.settle(2);
      await h.tester.fling(
        find.text('Message ready'),
        const Offset(0, -300),
        1500,
      );
      await h.settle();
      expect(find.byType(InAppNotificationBanner), findsNothing);
      expect(h.location, '/home');
    });

    appTest('system notification taps route through the app', (h) async {
      final notif = h.container.read(notificationServiceProvider);
      final call = h.backend.calls.first;

      notif.simulateTap('/calls/${call.id}');
      await h.settle();
      expect(h.location, '/calls/${call.id}');

      notif.simulateTap('/followups');
      await h.settle();
      expect(h.location, '/followups');

      notif.simulateTap('/callbacks');
      await h.settle();
      expect(h.location, '/callbacks');

      notif.simulateTap('');
      await h.settle();
      expect(h.location, '/home');
    });
  });
}

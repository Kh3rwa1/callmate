import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/utils/phone.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/followups/followup_detail_screen.dart';
import 'package:callpilot/features/followups/followup_message_card.dart';
import 'package:callpilot/services/whatsapp/whatsapp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';
import 'helpers/fake_whatsapp_service.dart';

/// Pending follow-ups in the order the list shows them.
List<FollowUp> _pending(MockBackend b) =>
    b.followUps.values.where((f) => f.isPending).toList()..sort((x, y) {
      final s = (y.scoreValue ?? 0).compareTo(x.scoreValue ?? 0);
      return s != 0 ? s : y.createdAt.compareTo(x.createdAt);
    });

FollowUp _topPending(MockBackend b) => _pending(b).first;

void main() {
  late FakeWhatsAppService wa;
  List<Override> Function() fakeWa([
    WhatsAppOpenResult result = WhatsAppOpenResult.opened,
  ]) =>
      () => [
        whatsappServiceProvider.overrideWithValue(
          wa = FakeWhatsAppService(result: result),
        ),
      ];

  group('FollowUpsScreen', () {
    appTest('lists pending drafts and opened ones', (h) async {
      final pending = _pending(h.backend);
      expect(find.text('Ready to send'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('followups-pending-count')),
          matching: find.text('${pending.length}'),
        ),
        findsOneWidget,
      );
      expect(find.text(pending.first.leadName), findsWidgets);
    }, location: '/followups');

    appTest('tapping a row opens the draft', (h) async {
      final top = _topPending(h.backend);
      await h.tap(find.text(top.leadName).first);
      expect(h.location, '/followups/${top.id}');
      expect(find.byType(FollowUpDetailScreen), findsOneWidget);
    }, location: '/followups');

    appTest(
      'WhatsApp button hands off and marks the draft opened',
      (h) async {
        final top = _topPending(h.backend);
        await h.tap(find.byTooltip('Open in WhatsApp').first);
        expect(wa.opened.single.phone, top.leadPhone);
        expect(wa.opened.single.message, top.message);
        final updated = h.backend.followUps[top.id]!;
        expect(updated.status, FollowUpStatus.opened);
        expect(updated.openedAt, isNotNull);
        expect(find.text('WhatsApp opened – tap Send there ✓'), findsOneWidget);
      },
      location: '/followups',
      overrides: fakeWa(),
    );

    appTest(
      'swiping a draft also hands off to WhatsApp',
      (h) async {
        final top = _topPending(h.backend);
        await h.tester.drag(
          find.text(top.leadName).first,
          const Offset(-600, 0),
        );
        await h.settle();
        expect(wa.opened.single.message, top.message);
        expect(h.backend.followUps[top.id]!.status, FollowUpStatus.opened);
      },
      location: '/followups',
      overrides: fakeWa(),
    );

    appTest(
      'empty inbox says all caught up',
      (h) async {
        expect(find.text('All caught up'), findsOneWidget);
        expect(find.text('Ready to send'), findsNothing);
      },
      location: '/followups',
      backend: () {
        final b = MockBackend();
        for (final f in b.followUps.values.toList()) {
          b.followUps[f.id] = f.copyWith(status: FollowUpStatus.done);
        }
        return b;
      },
    );

    appTest('opened drafts are listed and reopenable', (h) async {
      // Only keep one pending so the opened section is near the top.
      for (final f in _pending(h.backend).skip(1)) {
        h.backend.followUps[f.id] = f.copyWith(status: FollowUpStatus.opened);
      }
      h.backend.emitChanged('followups');
      await h.settle();
      expect(
        find.descendant(
          of: find.byKey(const Key('followups-pending-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await h.tester.scrollUntilVisible(
        find.byType(ListTile).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await h.tap(find.byType(ListTile).first);
      expect(h.location, startsWith('/followups/'));
      final id = h.location.split('/').last;
      expect(h.backend.followUps[id]!.isPending, isFalse);
      expect(find.text('WhatsApp opened'), findsWidgets);
    }, location: '/followups');
  });

  group('FollowUpDetailScreen', () {
    appTest('shows the drafted message and call summary', (h) async {
      final fu = _topPending(h.backend);
      await h.push('/followups/${fu.id}');
      expect(find.text('Follow-up ready'), findsOneWidget);
      expect(find.text(fu.leadName), findsOneWidget);
      expect(find.text(PhoneUtils.display(fu.leadPhone)), findsOneWidget);
      expect(find.text(fu.message), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      if (fu.callSummary != null) {
        expect(find.byKey(const Key('followup-call-summary')), findsOneWidget);
        await h.tapText(fu.callSummary!);
        expect(h.location, '/calls/${fu.callId}/result');
        expect(find.byType(CallResultScreen), findsOneWidget);
      }
    });

    appTest('editing and saving updates the draft', (h) async {
      final fu = _topPending(h.backend);
      await h.push('/followups/${fu.id}');
      await h.tapText('Edit');
      expect(find.text('Editing'), findsOneWidget);
      final field = find.descendant(
        of: find.byType(FollowUpMessageCard),
        matching: find.byType(TextField),
      );
      await h.tester.enterText(field, 'Hi! Fees are ₹52,000. Call us.');
      await h.tapText('Save');
      expect(
        h.backend.followUps[fu.id]!.message,
        'Hi! Fees are ₹52,000. Call us.',
      );
      expect(find.text('Message updated'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    appTest('tapping the message starts editing; unchanged save is a no-op', (
      h,
    ) async {
      final fu = _topPending(h.backend);
      await h.push('/followups/${fu.id}');
      await h.tapText(fu.message);
      expect(find.text('Editing'), findsOneWidget);
      await h.tapText('Save');
      expect(find.text('Message updated'), findsNothing);
      expect(h.backend.followUps[fu.id]!.message, fu.message);
    });

    appTest(
      'WhatsApp opens the edited text, then "I sent it" completes',
      (h) async {
        final fu = _topPending(h.backend);
        await h.push('/followups/${fu.id}');
        await h.tapText('Edit');
        await h.tester.enterText(
          find.descendant(
            of: find.byType(FollowUpMessageCard),
            matching: find.byType(TextField),
          ),
          'Edited text',
        );
        await h.tap(find.text('WhatsApp →'));
        expect(wa.opened.single.message, 'Edited text');
        expect(h.backend.followUps[fu.id]!.status, FollowUpStatus.opened);
        expect(h.backend.followUps[fu.id]!.message, 'Edited text');
        expect(find.text('WhatsApp opened'), findsOneWidget);

        // Returning from WhatsApp keeps the "opened" state.
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await h.settle(2);
        expect(find.text('WhatsApp opened'), findsOneWidget);

        await h.tap(find.widgetWithText(TextButton, 'I sent it'));
        expect(h.backend.followUps[fu.id]!.status, FollowUpStatus.done);
        expect(h.location, isNot('/followups/${fu.id}'));
      },
      location: '/followups',
      overrides: fakeWa(),
    );

    appTest(
      'menu copies, shares and dismisses',
      (h) async {
        final fu = _topPending(h.backend);
        await h.push('/followups/${fu.id}');

        await h.tap(find.byTooltip('More'));
        await h.tapText('Copy Message');
        expect(wa.copied, [fu.message]);
        expect(find.text('Message copied'), findsOneWidget);

        await h.tap(find.byTooltip('More'));
        await h.tapText('Share…');
        expect(wa.shared, [fu.message]);

        await h.tap(find.byTooltip('More'));
        expect(find.text('I sent it'), findsNothing); // still pending
        await h.tapText('Dismiss');
        expect(h.backend.followUps[fu.id]!.status, FollowUpStatus.dismissed);
        expect(h.location, '/followups');
      },
      location: '/followups',
      overrides: fakeWa(),
    );

    appTest('menu can mark an opened draft as sent', (h) async {
      final fu = h.backend.followUps.values.firstWhere(
        (f) => f.status == FollowUpStatus.opened,
      );
      await h.push('/followups/${fu.id}');
      expect(find.text('WhatsApp opened'), findsOneWidget);
      await h.tap(find.byTooltip('More'));
      await h.tap(find.widgetWithText(PopupMenuItem<String>, 'I sent it'));
      expect(h.backend.followUps[fu.id]!.status, FollowUpStatus.done);
    }, location: '/followups');

    appTest('unknown follow-up shows a friendly error', (h) async {
      await h.push('/followups/missing');
      expect(
        find.text("We couldn't find that. It may have been removed."),
        findsOneWidget,
      );
    });
  });

  group('WhatsApp handoff results', () {
    appTest(
      'invalid phone is reported and nothing is marked opened',
      (h) async {
        final fu = _topPending(h.backend);
        await h.push('/followups/${fu.id}');
        await h.tap(find.text('WhatsApp →'));
        expect(
          find.textContaining("This phone number doesn't look right"),
          findsOneWidget,
        );
        expect(h.backend.followUps[fu.id]!.status, fu.status);
        expect(find.text('Follow-up ready'), findsOneWidget);
      },
      location: '/followups',
      overrides: fakeWa(WhatsAppOpenResult.invalidPhone),
    );

    appTest(
      'empty message is reported',
      (h) async {
        final fu = _topPending(h.backend);
        await h.push('/followups/${fu.id}');
        await h.tap(find.text('WhatsApp →'));
        expect(
          find.text('The message is empty. Add some text first.'),
          findsOneWidget,
        );
      },
      location: '/followups',
      overrides: fakeWa(WhatsAppOpenResult.emptyMessage),
    );

    appTest(
      'not installed offers copy and share fallbacks',
      (h) async {
        final fu = _topPending(h.backend);
        await h.push('/followups/${fu.id}');
        await h.tap(find.text('WhatsApp →'));
        expect(find.text("WhatsApp isn't installed"), findsOneWidget);
        await h.tap(find.text('Copy Message').last);
        expect(wa.copied, [fu.message]);
        expect(find.text('Message copied'), findsOneWidget);
        expect(find.text("WhatsApp isn't installed"), findsNothing);

        // Let the snackbar clear before opening the sheet again.
        await h.tester.pump(const Duration(seconds: 5));
        await h.settle();
        await h.tap(find.text('WhatsApp →'));
        await h.tap(find.text('Share…').last);
        expect(wa.shared, [fu.message]);
        expect(h.backend.followUps[fu.id]!.status, FollowUpStatus.ready);
      },
      location: '/followups',
      overrides: fakeWa(WhatsAppOpenResult.notInstalled),
    );
  });
}

import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/widgets/app_card.dart';
import 'package:callpilot/core/utils/phone.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/leads/import_leads_screen.dart';
import 'package:callpilot/features/leads/lead_card.dart';
import 'package:callpilot/features/leads/lead_detail_screen.dart';
import 'package:callpilot/features/leads/lead_detail_widgets.dart';
import 'package:callpilot/features/voice_test/voice_test_screen.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';
import 'helpers/fake_whatsapp_service.dart';

/// Lead repository whose list() always fails.
class _FailingLeads extends MockLeadRepository {
  _FailingLeads(super.b);
  @override
  Future<Page<Lead>> list({
    String? query,
    LeadFilter filter = LeadFilter.all,
    String? cursor,
    int limit = 20,
  }) async => throw StateError('network down');
}

List<Lead> _visibleLeads(WidgetTester tester) => tester
    .widgetList<LeadCard>(find.byType(LeadCard))
    .map((c) => c.lead)
    .toList();

bool _chipSelected(String label) =>
    (find.widgetWithText(AppFilterChip, label).evaluate().single.widget
            as AppFilterChip)
        .selected;

Lead _byName(MockBackend b, String name) =>
    b.leads.values.firstWhere((l) => l.name == name);

void main() {
  group('LeadsScreen', () {
    appTest('lists leads with hot leads first', (h) async {
      final shown = _visibleLeads(h.tester);
      expect(shown, isNotEmpty);
      expect(shown.first.isHot, isTrue);
      expect(_chipSelected('All'), isTrue);
    }, location: '/leads');

    appTest('filter chips narrow the list', (h) async {
      await h.tapText('Hot');
      expect(_chipSelected('Hot'), isTrue);
      final hot = _visibleLeads(h.tester);
      expect(hot, isNotEmpty);
      expect(hot.every((l) => l.isHot), isTrue);

      await h.tapText('New');
      final fresh = _visibleLeads(h.tester);
      expect(fresh, isNotEmpty);
      expect(fresh.every((l) => l.status == LeadStatus.newLead), isTrue);

      await h.tapText('Call back');
      expect(
        _visibleLeads(
          h.tester,
        ).every((l) => l.status == LeadStatus.callback || l.callbackAt != null),
        isTrue,
      );
    }, location: '/leads');

    appTest('initial filter comes from the query string', (h) async {
      expect(_chipSelected('Warm'), isTrue);
      final warm = _visibleLeads(h.tester);
      expect(warm, isNotEmpty);
      expect(warm.every((l) => l.isWarm), isTrue);
    }, location: '/leads?filter=warm');

    appTest('search is debounced and can be cleared', (h) async {
      final before = _visibleLeads(h.tester).length;
      await h.tester.enterText(find.byType(TextField), 'Rahul');
      await h.tester.pump(const Duration(milliseconds: 100));
      expect(_visibleLeads(h.tester).length, before);

      await h.settle();
      final found = _visibleLeads(h.tester);
      expect(found.map((l) => l.name), ['Rahul Kumar']);

      await h.tap(find.byTooltip('Clear'));
      expect(_visibleLeads(h.tester).length, before);
    }, location: '/leads');

    appTest('search without matches shows an empty state', (h) async {
      await h.tester.enterText(find.byType(TextField), 'zzzz-nobody');
      await h.settle();
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('No customers match “zzzz-nobody”.'), findsOneWidget);
    }, location: '/leads');

    appTest(
      'hot filter with no hot leads explains why',
      (h) async {
        expect(find.text('No one ready to buy yet'), findsOneWidget);
      },
      location: '/leads?filter=hot',
      backend: () => MockBackend()..leads.removeWhere((_, l) => l.isHot),
    );

    appTest(
      'empty list offers to add leads',
      (h) async {
        expect(find.text('No customers here'), findsOneWidget);
        await h.tapText('Add customers');
        expect(h.location, '/leads/import');
      },
      location: '/leads',
      backend: () => MockBackend()..leads.clear(),
    );

    appTest(
      'load failure shows retry',
      (h) async {
        expect(find.text("Hmm, that didn't work"), findsOneWidget);
        expect(
          find.text('No connection. Check your internet and try again.'),
          findsOneWidget,
        );
      },
      location: '/leads',
      overrides: () => [
        leadRepoProvider.overrideWith(
          (ref) => _FailingLeads(ref.watch(mockBackendProvider)),
        ),
      ],
    );

    appTest('add button opens the import screen', (h) async {
      await h.tap(find.byTooltip('Add or import customers'));
      expect(h.location, '/leads/import');
      expect(find.byType(ImportLeadsScreen), findsOneWidget);
    }, location: '/leads');

    appTest('tapping a card opens the lead', (h) async {
      final lead = _visibleLeads(h.tester).first;
      await h.tapText(lead.name);
      expect(h.location, '/leads/${lead.id}');
      expect(find.byType(LeadDetailScreen), findsOneWidget);

      await h.go('/leads');
      await h.tap(find.byType(LeadCard).first);
      expect(h.location, startsWith('/leads/'));
    }, location: '/leads');

    appTest('WhatsApp on a lead with a pending draft opens the draft', (
      h,
    ) async {
      final lead = _visibleLeads(h.tester).first;
      final fu = h.backend.followUpForLead(lead.id)!;
      expect(fu.isPending, isTrue);
      await h.tap(find.byTooltip('WhatsApp').first);
      expect(h.location, '/followups/${fu.id}');
    }, location: '/leads');
  });

  group('LeadsScreen WhatsApp without a draft', () {
    late FakeWhatsAppService wa;
    appTest(
      'opens a greeting via the WhatsApp service',
      (h) async {
        // Business details load on Home; the card reads (not watches) them.
        await h.go('/leads');
        await h.tapText('New');
        final lead = _visibleLeads(h.tester).first;
        expect(h.backend.followUpForLead(lead.id), isNull);
        await h.tap(find.byTooltip('WhatsApp').first);
        expect(wa.opened, hasLength(1));
        expect(wa.opened.single.phone, lead.phone);
        expect(wa.opened.single.message, startsWith('Hi ${lead.firstName} 👋'));
        expect(wa.opened.single.message, contains(h.backend.business.name));
        expect(find.text('WhatsApp opened – tap Send there ✓'), findsOneWidget);
      },
      overrides: () => [
        whatsappServiceProvider.overrideWithValue(wa = FakeWhatsAppService()),
      ],
    );
  });

  group('LeadDetailScreen', () {
    appTest('shows profile, details, signals and history', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      await h.push('/leads/${rahul.id}');

      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text(PhoneUtils.display(rahul.phone)), findsOneWidget);
      expect(find.text('AI summary'), findsOneWidget);
      expect(find.text(rahul.summary!), findsOneWidget);
      expect(find.byType(LeadDetailRow), findsWidgets);
      expect(find.text('Next action'), findsOneWidget);
      expect(find.text(rahul.nextAction.label), findsWidgets);

      final signals =
          rahul.score!.positiveSignals.length + rahul.objections.length;
      if (signals > 0) {
        expect(find.text('Signals'), findsOneWidget);
        expect(find.byType(LeadSignalChip), findsNWidgets(signals));
      }

      await h.tester.scrollUntilVisible(
        find.text('Call history'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      final calls = h.backend.calls.where((c) => c.leadId == rahul.id).length;
      expect(find.text('$calls'), findsWidgets);
    });

    appTest('follow-up card and WhatsApp open the pending draft', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      final fu = h.backend.followUpForLead(rahul.id)!;
      await h.push('/leads/${rahul.id}');

      await h.tap(find.widgetWithText(FilledButton, 'WhatsApp'));
      expect(h.location, '/followups/${fu.id}');

      h.router.pop();
      await h.settle();
      await h.tapText('Review & send');
      expect(h.location, '/followups/${fu.id}');
    });

    appTest('summary links to the full call result', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      final connected = h.backend.calls.firstWhere(
        (c) => c.leadId == rahul.id && c.status.isConnected,
      );
      await h.push('/leads/${rahul.id}');
      await h.tapText('Full call result');
      expect(h.location, '/calls/${connected.id}/result');
    });

    appTest('AI call option triggers a call and reports it', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      final before = h.backend.calls.length;
      await h.push('/leads/${rahul.id}');

      await h.tap(find.byTooltip('AI Call'));
      expect(find.text('Call Rahul Kumar'), findsOneWidget);
      await h.tapText('AI call by ${h.backend.agent.name}');

      expect(h.backend.calls.length, before + 1);
      expect(h.backend.calls.last.leadId, rahul.id);
      // "Calling…" is replaced by the confirmation once the call is placed.
      expect(find.text('Calling Rahul Kumar…'), findsNothing);
      expect(
        find.text('${h.backend.agent.name} is calling Rahul Kumar'),
        findsOneWidget,
      );
    });

    appTest('in-app option opens the voice test', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      await h.push('/leads/${rahul.id}');
      await h.tap(find.byTooltip('AI Call'));
      await h.tapText('Talk in-app with ${h.backend.agent.name}');
      expect(h.location, '/voice-test');
      expect(find.byType(VoiceTestScreen), findsOneWidget);
    });

    appTest('dismissing the call sheet does nothing', (h) async {
      final rahul = _byName(h.backend, 'Rahul Kumar');
      final before = h.backend.calls.length;
      await h.push('/leads/${rahul.id}');
      await h.tap(find.byTooltip('AI Call'));
      await h.tester.tapAt(const Offset(400, 20));
      await h.settle();
      expect(find.text('Call Rahul Kumar'), findsNothing);
      expect(h.backend.calls.length, before);
      expect(h.location, '/leads/${rahul.id}');
    });

    appTest('callback sheet schedules a callback', (h) async {
      final lead = h.backend.leads.values.firstWhere(
        (l) => l.status == LeadStatus.newLead,
      );
      await h.push('/leads/${lead.id}');
      expect(
        find.text(
          "${h.backend.agent.name} hasn't called ${lead.firstName} yet.",
        ),
        findsOneWidget,
      );

      await h.tap(find.byTooltip('Call back'));
      expect(find.text('Schedule call back'), findsOneWidget);
      await h.tapText('Tomorrow, 11 AM');
      await h.tap(find.widgetWithText(FilledButton, 'Schedule Call Back'));

      final cb = h.backend.callbacks.values.singleWhere(
        (c) => c.leadId == lead.id && c.status == CallbackStatus.scheduled,
      );
      final now = DateTime.now();
      expect(cb.scheduledAt, DateTime(now.year, now.month, now.day + 1, 11));
      expect(h.backend.leads[lead.id]!.status, LeadStatus.callback);
      expect(find.textContaining('Call back set for'), findsOneWidget);
    });

    appTest('unknown lead shows a friendly error', (h) async {
      await h.push('/leads/does-not-exist');
      expect(
        find.text("We couldn't find that. It may have been removed."),
        findsOneWidget,
      );
    });
  });
}

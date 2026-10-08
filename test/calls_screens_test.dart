import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/calls/calls_screen.dart';
import 'package:callpilot/features/calls/transcript_view.dart';
import 'package:callpilot/features/followups/followup_detail_screen.dart';
import 'package:callpilot/features/leads/lead_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

List<Call> _visibleCalls(WidgetTester tester) => tester
    .widgetList<CallCard>(find.byType(CallCard))
    .map((c) => c.call)
    .toList();

bool _chipSelected(String label) =>
    (find.widgetWithText(ChoiceChip, label).evaluate().single.widget
            as ChoiceChip)
        .selected;

void main() {
  group('CallsScreen', () {
    appTest('lists the AI employee\'s calls', (h) async {
      expect(find.text('AI Calls'), findsOneWidget);
      expect(
        find.text('Everything ${h.backend.agent.name} did for you'),
        findsOneWidget,
      );
      expect(_visibleCalls(h.tester), isNotEmpty);
      expect(_chipSelected('All'), isTrue);
    }, location: '/calls');

    appTest('filter chips narrow the list', (h) async {
      await h.tapText('Connected');
      var shown = _visibleCalls(h.tester);
      expect(shown, isNotEmpty);
      expect(shown.every((c) => c.status.isConnected), isTrue);

      await h.tapText('No Answer');
      shown = _visibleCalls(h.tester);
      expect(shown, isNotEmpty);
      expect(
        shown.every(
          (c) => c.status == CallStatus.noAnswer || c.status == CallStatus.busy,
        ),
        isTrue,
      );

      await h.tapText('🔥 Hot');
      shown = _visibleCalls(h.tester);
      expect(shown, isNotEmpty);
      expect(shown.every((c) => c.isHot), isTrue);
    }, location: '/calls');

    appTest(
      'initial filter comes from the query string',
      (h) async {
        expect(_chipSelected('No Answer'), isTrue);
        expect(
          _visibleCalls(h.tester).every((c) => !c.status.isConnected),
          isTrue,
        );
      },
      location: '/calls?filter=no_answer',
    );

    appTest('connected call opens the result screen', (h) async {
      await h.tapText('Connected');
      final call = _visibleCalls(h.tester).first;
      await h.tap(find.byType(CallCard).first);
      expect(h.location, '/calls/${call.id}/result');
      expect(find.text('Call completed ✓'), findsOneWidget);
      expect(find.text('AI SUMMARY'), findsOneWidget);
      expect(find.text('LEAD SCORE'), findsOneWidget);
    }, location: '/calls');

    appTest('unanswered call opens the detail view', (h) async {
      await h.tapText('No Answer');
      final call = _visibleCalls(h.tester).first;
      await h.tap(find.byType(CallCard).first);
      expect(h.location, '/calls/${call.id}');
      expect(find.text('Call details'), findsOneWidget);
      expect(find.text(call.status.label), findsWidgets);
      expect(
        find.textContaining('will try again in the next campaign'),
        findsOneWidget,
      );

      await h.tapText('Open lead');
      expect(h.location, '/leads/${call.leadId}');
      expect(find.byType(LeadDetailScreen), findsOneWidget);
    }, location: '/calls');

    appTest(
      'empty log invites starting a campaign',
      (h) async {
        expect(
          find.text("${h.backend.agent.name} hasn't made any calls yet."),
          findsOneWidget,
        );
        await h.tapText('Call New Leads');
        expect(h.location, '/campaign/new');
      },
      location: '/calls',
      backend: () => MockBackend()..calls.clear(),
    );
  });

  group('CallResultScreen', () {
    appTest('Prepare WhatsApp opens the drafted follow-up', (h) async {
      final call = h.backend.simulateCall(LeadTemperature.hot);
      expect(call.followUpId, isNotNull);
      await h.push('/calls/${call.id}/result');
      expect(find.textContaining(call.leadName), findsWidgets);
      await h.tapText('Prepare WhatsApp');
      expect(h.location, '/followups/${call.followUpId}');
      expect(find.byType(FollowUpDetailScreen), findsOneWidget);
    });

    appTest('without a follow-up Prepare WhatsApp opens the lead', (h) async {
      final call = h.backend.calls.firstWhere(
        (c) => c.status.isConnected && c.followUpId == null,
      );
      await h.push('/calls/${call.id}/result');
      await h.tapText('Prepare WhatsApp');
      expect(h.location, '/leads/${call.leadId}');
    });

    appTest('Schedule Callback books a callback for the lead', (h) async {
      final call = h.backend.simulateCall(LeadTemperature.warm);
      await h.push('/calls/${call.id}/result');
      await h.tap(find.widgetWithText(OutlinedButton, 'Schedule Callback'));
      expect(find.text('Schedule callback'), findsOneWidget);
      await h.tap(find.widgetWithText(FilledButton, 'Schedule Callback'));
      expect(
        h.backend.callbacks.values.where(
          (c) =>
              c.leadId == call.leadId && c.status == CallbackStatus.scheduled,
        ),
        hasLength(1),
      );
      expect(find.textContaining('Callback set for'), findsOneWidget);
    });

    appTest('detail-only route shows the call facts', (h) async {
      final call = h.backend.calls.firstWhere((c) => c.status.isConnected);
      await h.push('/calls/${call.id}');
      expect(find.byType(CallResultScreen), findsOneWidget);
      expect(find.text('Call details'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Call completed ✓'), findsNothing);
    });

    appTest('missing call shows a friendly error', (h) async {
      await h.push('/calls/nope/result');
      expect(find.text("Hmm, that didn't work"), findsOneWidget);
    });
  });

  group('TranscriptView', () {
    const transcript = CallTranscript(
      lines: [
        TranscriptLine(
          speaker: TranscriptSpeaker.agent,
          text: 'Hello!',
          offset: Duration(seconds: 1),
        ),
        TranscriptLine(speaker: TranscriptSpeaker.lead, text: 'Hi there'),
        TranscriptLine(speaker: TranscriptSpeaker.agent, text: 'Fees?'),
        TranscriptLine(speaker: TranscriptSpeaker.lead, text: 'Yes please'),
      ],
    );

    Future<void> pump(WidgetTester tester, {int? maxLines}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TranscriptView(
                  transcript: transcript,
                  leadName: 'Rahul',
                  agentName: 'Riya',
                  maxLines: maxLines,
                ),
              ),
            ),
          ),
        );

    testWidgets('collapses long transcripts until expanded', (tester) async {
      await pump(tester, maxLines: 2);
      expect(find.byType(TranscriptBubble), findsNWidgets(2));
      expect(find.text('Yes please'), findsNothing);

      await tester.tap(find.text('Show full transcript (4 lines)'));
      await tester.pump();
      expect(find.byType(TranscriptBubble), findsNWidgets(4));
      expect(find.text('Yes please'), findsOneWidget);
      expect(find.textContaining('Show full transcript'), findsNothing);
    });

    testWidgets('labels speakers and offsets', (tester) async {
      await pump(tester);
      expect(find.byType(TranscriptBubble), findsNWidgets(4));
      expect(find.text('Riya'), findsNWidgets(2));
      expect(find.text('Rahul'), findsNWidgets(2));
      expect(find.text('  00:01'), findsOneWidget);
      expect(find.bySemanticsLabel('Riya said: Hello!'), findsOneWidget);
    });
  });
}

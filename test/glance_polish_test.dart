import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/followups/followups_screen.dart';
import 'package:callpilot/features/leads/lead_card.dart';
import 'package:callpilot/l10n/s.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

LeadScore _score(LeadTemperature t, LeadIntent i) => LeadScore(
  value: 50,
  temperature: t,
  intent: i,
  positiveSignals: const [],
  concerns: const [],
);

void main() {
  group('followUpPreview', () {
    test('skips the greeting and the "here are the details:" lead-in', () {
      expect(
        followUpPreview(
          'Hi Rahul 👋\n\nGreat speaking with you today. As discussed, here '
          'are the details:\n\n📌 NEET – Evening\n💰 ₹52,000 / year',
        ),
        '📌 NEET – Evening 💰 ₹52,000 / year',
      );
    });

    test('keeps a colon that is part of the real content', () {
      const text =
          'Thanks for asking. Our weekend batch starts on Saturday and the '
          'fee is: ₹38,000 / year.';
      expect(followUpPreview(text), text);
      expect(followUpPreview('Fees: ₹24,000'), '₹24,000');
      expect(followUpPreview('Details:'), 'Details:');
    });
  });

  group('call result headline', () {
    test('drops an intent that only repeats the headline', () {
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.cold, LeadIntent.notInterested),
        ),
        isFalse,
      );
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.hot, LeadIntent.interested),
        ),
        isFalse,
      );
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.warm, LeadIntent.exploring),
        ),
        isFalse,
      );
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.hot, LeadIntent.unknown),
        ),
        isFalse,
      );
    });

    test('keeps an intent that adds something', () {
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.warm, LeadIntent.callbackRequested),
        ),
        isTrue,
      );
      expect(
        intentAddsToTemperature(
          _score(LeadTemperature.hot, LeadIntent.exploring),
        ),
        isTrue,
      );
    });
  });

  group('Messages list', () {
    appTest('previews what the customer wants, from the call', (h) async {
      final fu = h.backend.followUps.values.firstWhere(
        (f) => f.isPending && (f.callSummary ?? '').isNotEmpty,
      );
      expect(find.text(fu.callSummary!.trim()), findsWidgets);
      expect(
        find.textContaining('As discussed, here are the details'),
        findsNothing,
      );
    }, location: '/followups');
  });

  group('Customers list', () {
    appTest('shows the whole interest line, not "NEET ·…"', (h) async {
      final card = h.tester
          .widgetList<LeadCard>(find.byType(LeadCard))
          .firstWhere((c) => c.lead.attributes.isNotEmpty);
      final meta = leadInterestLine(S.en, card.lead);
      final text = find.descendant(
        of: find.byWidget(card),
        matching: find.text(meta),
      );
      expect(text, findsOneWidget);
      final painter = TextPainter(
        text: TextSpan(text: meta, style: h.tester.widget<Text>(text).style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: h.tester.getSize(text).width);
      expect(painter.didExceedMaxLines, isFalse);
    }, location: '/leads');
  });
}

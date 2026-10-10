import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/widgets/lead_widgets.dart';
import 'package:callpilot/data/models/models.dart';

void main() {
  testWidgets('ScoreBadge shows number + word (not colour alone)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ScoreBadge(
              score: LeadScore(
                value: 87,
                temperature: LeadTemperature.hot,
                intent: LeadIntent.interested,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Wants to buy'), findsOneWidget);
    expect(find.textContaining('87'), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
  });

  testWidgets(
    'list badges use short words; screen readers hear the full words',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ScoreBadge(
                    score: LeadScore(
                      value: 20,
                      temperature: LeadTemperature.cold,
                      intent: LeadIntent.unknown,
                    ),
                  ),
                  ScoreBadge(
                    score: LeadScore(
                      value: 55,
                      temperature: LeadTemperature.warm,
                      intent: LeadIntent.exploring,
                    ),
                  ),
                  ScoreBadge(
                    large: true,
                    score: LeadScore(
                      value: 20,
                      temperature: LeadTemperature.cold,
                      intent: LeadIntent.unknown,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Compact badges: short enough to never be cut off in a 412 dp list row.
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Thinking'), findsOneWidget);
      // Large badge (detail screens) keeps the full words.
      expect(find.text('Not interested now'), findsOneWidget);
      expect(find.bySemanticsLabel('Not interested now'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Thinking about it'), findsOneWidget);
      handle.dispose();
    },
  );
}

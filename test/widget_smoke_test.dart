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
    expect(find.text('87 · Hot'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
  });
}

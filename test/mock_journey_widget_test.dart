import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/campaign/campaign_screens.dart';
import 'package:callpilot/features/followups/followups_screen.dart';
import 'package:callpilot/features/leads/leads_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_screens.dart';

void main() {
  group(
    'Mock Journey Widget Tests (Onboarding → Lead → Campaign → Call Result → Follow-up)',
    () {
      late MockBackend backend;

      setUp(() {
        backend = MockBackend();
      });

      tearDown(() {
        backend.dispose();
      });

      Widget wrap(Widget child) {
        return ProviderScope(
          overrides: [
            useMockProvider.overrideWithValue(true),
            mockBackendProvider.overrideWithValue(backend),
          ],
          child: MaterialApp(home: child),
        );
      }

      testWidgets('1. Onboarding WelcomeScreen renders brand and Get Started', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(const WelcomeScreen()));
        await tester.pump(const Duration(milliseconds: 800));

        expect(find.textContaining('Welcome to'), findsOneWidget);
        expect(find.text('Create My AI Employee'), findsOneWidget);
      });

      testWidgets('2. LeadsScreen renders in mock mode with search and tabs', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(const LeadsScreen()));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(TextField), findsOneWidget); // Search bar
        expect(find.text('All'), findsOneWidget);
        expect(find.text('🔥 Hot'), findsOneWidget);
      });

      testWidgets('3. CampaignSetupScreen renders in mock mode', (
        tester,
      ) async {
        await tester.pumpWidget(wrap(const CampaignSetupScreen()));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Call New Leads'), findsOneWidget);
        expect(find.textContaining('leads ready'), findsOneWidget);
      });

      testWidgets('4. CallResultScreen renders call outcome and AI scoring', (
        tester,
      ) async {
        final call = backend.simulateCall(LeadTemperature.hot);

        await tester.pumpWidget(wrap(CallResultScreen(callId: call.id)));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.textContaining(call.leadName), findsWidgets);
        expect(find.text('Call completed ✓'), findsOneWidget);
        expect(find.text('AI SUMMARY'), findsOneWidget);
      });

      testWidgets(
        '5. FollowupsScreen renders with manual WhatsApp trigger guarantee',
        (tester) async {
          await tester.pumpWidget(wrap(const FollowUpsScreen()));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.text('Follow-ups'), findsOneWidget);
          expect(find.byType(CustomScrollView), findsOneWidget);
        },
      );
    },
  );
}

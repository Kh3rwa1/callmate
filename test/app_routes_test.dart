import 'package:callpilot/features/agent/agent_screen.dart';
import 'package:callpilot/features/callbacks/callbacks_screen.dart';
import 'package:callpilot/features/calls/call_result_screen.dart';
import 'package:callpilot/features/calls/calls_screen.dart';
import 'package:callpilot/features/followups/followup_detail_screen.dart';
import 'package:callpilot/features/followups/followups_screen.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/leads/import_leads_screen.dart';
import 'package:callpilot/features/leads/lead_detail_screen.dart';
import 'package:callpilot/features/leads/leads_screen.dart';
import 'package:callpilot/features/notifications/notifications_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_screens.dart';
import 'package:callpilot/features/usage/usage_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

void main() {
  group('Router', () {
    appTest('boots into the home tab when onboarded', (h) async {
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    appTest('redirects to onboarding when not onboarded', (h) async {
      await h.go('/leads');
      expect(h.location, '/onboarding');
      expect(find.byType(BusinessTypeScreen), findsOneWidget);
    }, onboarded: false);

    appTest('main tabs render their screens', (h) async {
      await h.go('/leads');
      expect(find.byType(LeadsScreen), findsOneWidget);
      await h.go('/calls');
      expect(find.byType(CallsScreen), findsOneWidget);
      await h.go('/followups');
      expect(find.byType(FollowUpsScreen), findsOneWidget);
      await h.go('/agent');
      expect(find.byType(AgentScreen), findsOneWidget);
    });

    appTest('detail routes resolve their path parameters', (h) async {
      final lead = h.backend.leads.values.first;
      await h.push('/leads/${lead.id}');
      expect(find.byType(LeadDetailScreen), findsOneWidget);
      expect(find.textContaining(lead.name), findsWidgets);

      final call = h.backend.calls.first;
      await h.push('/calls/${call.id}');
      expect(find.byType(CallResultScreen), findsOneWidget);

      final fu = h.backend.followUps.values.first;
      await h.push('/followups/${fu.id}');
      expect(find.byType(FollowUpDetailScreen), findsOneWidget);
    });

    appTest('secondary full-screen routes render', (h) async {
      await h.push('/leads/import');
      expect(find.byType(ImportLeadsScreen), findsOneWidget);
      await h.go('/home');
      await h.push('/callbacks');
      expect(find.byType(CallbacksScreen), findsOneWidget);
      await h.go('/home');
      await h.push('/notifications');
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await h.go('/home');
      await h.push('/usage');
      expect(find.byType(UsageScreen), findsOneWidget);
    });
  });
}

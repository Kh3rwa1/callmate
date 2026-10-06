import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent/agent_screen.dart';
import '../../features/agent/edit_agent_screen.dart';
import '../../features/callbacks/callbacks_screen.dart';
import '../../features/calls/call_result_screen.dart';
import '../../features/calls/calls_screen.dart';
import '../../features/campaign/campaign_screens.dart';
import '../../features/demo/demo_screen.dart';
import '../../features/followups/followup_detail_screen.dart';
import '../../features/followups/followups_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/knowledge/teach_ai_screen.dart';
import '../../features/leads/import_leads_screen.dart';
import '../../features/leads/lead_detail_screen.dart';
import '../../features/leads/leads_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/onboarding_screens.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/usage/usage_screen.dart';
import '../../features/voice_test/voice_test_screen.dart';
import '../providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage(
  key: s.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 280),
  transitionsBuilder: (_, a, __, c) => FadeTransition(
    opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
    child: SlideTransition(
      position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: c,
    ),
  ),
);

final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(localPrefsProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final inOnboarding = loc.startsWith('/onboarding') || loc.startsWith('/voice-test');
      if (!prefs.onboarded && !inOnboarding && loc != '/demo' && loc != '/splash') return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

      // ---------------- Onboarding
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => _fade(s, const WelcomeScreen()),
        routes: [
          GoRoute(path: 'business-type', pageBuilder: (_, s) => _fade(s, const BusinessTypeScreen())),
          GoRoute(path: 'skills', pageBuilder: (_, s) => _fade(s, const EmployeeSkillsScreen())),
          GoRoute(path: 'details', pageBuilder: (_, s) => _fade(s, const BusinessDetailsScreen())),
          GoRoute(path: 'offer', pageBuilder: (_, s) => _fade(s, const OfferDetailsScreen())),
          GoRoute(path: 'teach', pageBuilder: (_, s) => _fade(s, const TeachAiOnboardingScreen())),
          GoRoute(path: 'create', pageBuilder: (_, s) => _fade(s, const CreateAgentScreen())),
          GoRoute(path: 'test', pageBuilder: (_, s) => _fade(s, const FirstCallScreen())),
        ],
      ),

      // ---------------- Main app: exactly 5 tabs
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leads',
                builder: (_, s) => LeadsScreen(initialFilter: s.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calls',
                builder: (_, s) => CallsScreen(initialFilter: s.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/followups', builder: (_, __) => const FollowUpsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/agent', builder: (_, __) => const AgentScreen())],
          ),
        ],
      ),

      // ---------------- Full-screen flows (pushed on root navigator)
      GoRoute(path: '/leads/import', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const ImportLeadsScreen())),
      GoRoute(
        path: '/leads/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _fade(s, LeadDetailScreen(leadId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/calls/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _fade(s, CallResultScreen(callId: s.pathParameters['id']!, detailOnly: true)),
        routes: [
          GoRoute(
            path: 'result',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (_, s) => _fade(s, CallResultScreen(callId: s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/followups/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _fade(s, FollowUpDetailScreen(followUpId: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/campaign/new', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const CampaignSetupScreen())),
      GoRoute(
        path: '/campaigns/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _fade(s, CampaignProgressScreen(campaignId: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/agent/edit', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const EditAgentScreen())),
      GoRoute(path: '/agent/teach', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const TeachAiScreen())),
      GoRoute(
        path: '/voice-test',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _fade(s, VoiceTestScreen(fromOnboarding: s.uri.queryParameters['from'] == 'onboarding')),
      ),
      GoRoute(path: '/callbacks', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const CallbacksScreen())),
      GoRoute(path: '/notifications', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const NotificationsScreen())),
      GoRoute(path: '/usage', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const UsageScreen())),
      GoRoute(path: '/demo', parentNavigatorKey: rootNavigatorKey, pageBuilder: (_, s) => _fade(s, const DemoScreen())),
    ],
  );
});

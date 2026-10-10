import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent/agent_screen.dart';
import '../../features/agent/edit_agent_screen.dart';
import '../../features/agent/playbook_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/callbacks/callbacks_screen.dart';
import '../../features/calls/call_result_screen.dart';
import '../../features/calls/calls_screen.dart';
import '../../features/campaign/campaign_screens.dart';
import '../../features/demo/demo_screen.dart';
import '../../features/followups/followup_detail_screen.dart';
import '../../features/followups/followups_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/knowledge/teach_ai_screen.dart';
import '../../features/language/language_pick_screen.dart';
import '../../features/leads/contacts_picker_screen.dart';
import '../../features/leads/import_leads_screen.dart';
import '../../features/leads/lead_capture_screen.dart';
import '../../features/leads/lead_detail_screen.dart';
import '../../features/leads/leads_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/onboarding_screens.dart';
import '../../features/referrals/invite_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/usage/usage_screen.dart';
import '../../features/voice_test/voice_test_screen.dart';
import '../motion/motion.dart';
import '../providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Pushed screens: shared-axis ("forward") transition.
CustomTransitionPage<void> _page(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: sharedAxisTransition,
    );

/// Places you arrive at rather than go "forward" to (sign-in, the app).
CustomTransitionPage<void> _arrive(GoRouterState s, Widget child) =>
    CustomTransitionPage(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: fadeThroughTransition,
    );

/// The router is created once. Session changes re-run [GoRouter.redirect] via
/// `refreshListenable` instead of rebuilding the router, which would restart
/// at /splash and drop the navigation stack on every login/logout.
final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.read(localPrefsProvider);
  final sessionChanges = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => sessionChanges.value++);
  ref.onDispose(sessionChanges.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: sessionChanges,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final hasSession = ref.read(sessionProvider).value ?? false;
      final isMock = ref.read(useMockProvider);
      final inAuth = loc.startsWith('/login');
      final inOnboarding =
          loc.startsWith('/onboarding') || loc.startsWith('/voice-test');

      if (!isMock &&
          !hasSession &&
          !inAuth &&
          loc != '/demo' &&
          loc != '/splash' &&
          loc != '/language') {
        return '/login';
      }
      if (hasSession && inAuth) {
        return prefs.onboarded ? '/home' : '/onboarding';
      }
      if (!prefs.onboarded &&
          !inOnboarding &&
          loc != '/demo' &&
          loc != '/splash' &&
          loc != '/language' &&
          !inAuth) {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/language',
        pageBuilder: (_, s) => _arrive(s, const LanguagePickScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => _arrive(s, const LoginScreen()),
      ),

      // ---------------- Onboarding (3 steps)
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => _arrive(s, const BusinessTypeScreen()),
        routes: [
          GoRoute(
            path: 'name',
            pageBuilder: (_, s) => _page(s, const NameVoiceScreen()),
          ),
          GoRoute(
            path: 'hear',
            pageBuilder: (_, s) => _page(s, const HearAiScreen()),
          ),
          // Steps of the old 7-step flow (old links, notifications).
          for (final old in const ['business-type'])
            GoRoute(path: old, redirect: (_, _) => '/onboarding'),
          for (final old in const [
            'skills',
            'details',
            'offer',
            'teach',
            'create',
          ])
            GoRoute(path: old, redirect: (_, _) => '/onboarding/name'),
          GoRoute(path: 'test', redirect: (_, _) => '/onboarding/hear'),
        ],
      ),

      // ---------------- Main app: exactly 5 tabs
      StatefulShellRoute(
        pageBuilder: (_, s, shell) => _arrive(s, AppShell(shell: shell)),
        navigatorContainerBuilder: (_, shell, children) =>
            FadeThroughBranches(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leads',
                builder: (_, s) =>
                    LeadsScreen(initialFilter: s.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calls',
                builder: (_, s) =>
                    CallsScreen(initialFilter: s.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/followups',
                builder: (_, _) => const FollowUpsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/agent', builder: (_, _) => const AgentScreen()),
            ],
          ),
        ],
      ),

      // ---------------- Full-screen flows (pushed on root navigator)
      GoRoute(
        path: '/leads/import',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const ImportLeadsScreen()),
      ),
      GoRoute(
        path: '/leads/auto',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const LeadCaptureScreen()),
      ),
      GoRoute(
        path: '/leads/contacts',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const ContactsPickerScreen()),
      ),
      GoRoute(
        path: '/leads/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) =>
            _page(s, LeadDetailScreen(leadId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/calls/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(
          s,
          CallResultScreen(callId: s.pathParameters['id']!, detailOnly: true),
        ),
        routes: [
          GoRoute(
            path: 'result',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (_, s) =>
                _page(s, CallResultScreen(callId: s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/followups/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) =>
            _page(s, FollowUpDetailScreen(followUpId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/campaign/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const CampaignSetupScreen()),
      ),
      GoRoute(
        path: '/campaigns/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(
          s,
          CampaignProgressScreen(campaignId: s.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/agent/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const EditAgentScreen()),
      ),
      GoRoute(
        path: '/agent/playbook',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const PlaybookScreen()),
      ),
      GoRoute(
        path: '/agent/teach',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const TeachAiScreen()),
      ),
      GoRoute(
        path: '/voice-test',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(
          s,
          VoiceTestScreen(
            fromOnboarding: s.uri.queryParameters['from'] == 'onboarding',
          ),
        ),
      ),
      GoRoute(
        path: '/callbacks',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const CallbacksScreen()),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/usage',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(
          s,
          UsageScreen(openTopup: s.uri.queryParameters['topup'] == '1'),
        ),
      ),
      GoRoute(
        path: '/invite',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const InviteScreen()),
      ),
      GoRoute(
        path: '/demo',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, s) => _page(s, const DemoScreen()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

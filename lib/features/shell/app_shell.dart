import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

/// Bottom navigation: exactly Home · Leads · Calls · Follow-ups · AI Employee.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(dashboardProvider).value?.followUpsReady ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Leads'),
          const NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call_rounded), label: 'Calls'),
          NavigationDestination(
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.chat_bubble_rounded)),
            label: 'Follow-ups',
          ),
          const NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent_rounded),
            label: 'AI Employee',
          ),
        ],
      ),
    );
  }
}

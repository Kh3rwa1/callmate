import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';

/// Development / demo controls – lets the full loop be demoed without
/// live telephony. Hidden in prod flavor.
class DemoScreen extends ConsumerWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final mock = ref.watch(useMockProvider);
    if (!mock) {
      return Scaffold(
        appBar: AppBar(title: const Text('Demo controls')),
        body: const Center(
          child: Text('Demo controls are only available in mock mode.'),
        ),
      );
    }
    final b = ref.read(mockBackendProvider);
    final notif = ref.read(notificationServiceProvider);

    void snack(String s) => ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(s)));

    Widget tile(String emoji, String title, String sub, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            onTap: onTap,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconBubble(color: AppColors.surfaceMuted, child: Emoji(emoji)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.titleSmall),
                      Text(sub, style: t.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.play_arrow_rounded, color: AppColors.brand),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Demo controls')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
        children: [
          AppCard(
            color: AppColors.warmSoft,
            shadow: false,
            padding: const EdgeInsets.all(14),
            child: Text(
              'Mock backend active. These actions run the same pipeline the real Sarvam webhook will: '
              'call → structured AI output → score → follow-up → notification.',
              style: t.bodyMedium?.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(height: 18),
          tile(
            '🔥',
            'Simulate hot lead',
            'A new lead is called and scores 80+',
            () {
              final c = b.simulateCall(LeadTemperature.hot);
              snack('${c.leadName} – score ${c.leadScore?.value}');
              context.push('/calls/${c.id}/result');
            },
          ),
          tile(
            '📞',
            'Simulate call completed',
            'A warm lead, follow-up drafted',
            () {
              final c = b.simulateCall(LeadTemperature.warm);
              context.push('/calls/${c.id}/result');
            },
          ),
          tile(
            '💬',
            'Simulate WhatsApp follow-up',
            'Opens the newest follow-up draft',
            () {
              final c = b.simulateCall(LeadTemperature.hot);
              if (c.followUpId != null) {
                context.push('/followups/${c.followUpId}');
              }
            },
          ),
          tile(
            '🚀',
            'Simulate campaign progress',
            'Start calling all new leads',
            () => context.push('/campaign/new'),
          ),
          const SectionLabel('Notifications'),
          tile(
            '🔥',
            'Hot lead notification',
            'Tap the banner to deep-link',
            () =>
                notif.present(b.simulateNotification(NotificationType.hotLead)),
          ),
          tile(
            '💬',
            'Follow-up ready notification',
            'Deep-links to the follow-up',
            () => notif.present(
              b.simulateNotification(NotificationType.followUpReady),
            ),
          ),
          tile(
            '📅',
            'Callback notification',
            'Deep-links to the lead',
            () => notif.present(
              b.simulateNotification(NotificationType.callback),
            ),
          ),
          const SectionLabel('Reset'),
          tile(
            '↩️',
            'Replay onboarding',
            'Start again from “Hire your AI employee”',
            () async {
              await ref.read(localPrefsProvider).reset();
              if (context.mounted) context.go('/onboarding');
            },
          ),
        ],
      ),
    );
  }
}

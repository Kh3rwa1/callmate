import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Development / demo controls – lets the full loop be demoed without
/// live telephony. Hidden in prod flavor.
class DemoScreen extends ConsumerWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final mock = ref.watch(useMockProvider);
    if (!mock) {
      return Scaffold(
        appBar: AppBar(title: Text(s.demoControls)),
        body: Center(child: Text(s.mockOnly)),
      );
    }
    final b = ref.read(mockBackendProvider);
    final notif = ref.read(notificationServiceProvider);

    void snack(String m) => ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));

    Widget row(IconData icon, String title, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        child: Row(
          children: [
            Icon(icon, size: 21, color: AppColors.inkSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: t.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.inkFaint),
          ],
        ),
      ),
    );

    Widget group(List<Widget> rows) => AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 51, endIndent: 16),
            rows[i],
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.demoControls)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(
              label: s.mockBackend,
              color: AppColors.warmInk,
              background: AppColors.warmSoft,
              icon: Icon(
                Icons.science_outlined,
                size: 14,
                color: AppColors.warmInk,
              ),
            ),
          ),
          SectionLabel(s.simulate),
          group([
            row(Icons.local_fire_department_outlined, 'Simulate hot lead', () {
              final c = b.simulateCall(LeadTemperature.hot);
              snack('${c.leadName} – score ${c.leadScore?.value}');
              context.push('/calls/${c.id}/result');
            }),
            row(Icons.call_outlined, 'Simulate call completed', () {
              final c = b.simulateCall(LeadTemperature.warm);
              context.push('/calls/${c.id}/result');
            }),
            row(
              Icons.chat_bubble_outline_rounded,
              'Simulate WhatsApp follow-up',
              () {
                final c = b.simulateCall(LeadTemperature.hot);
                if (c.followUpId != null) {
                  context.push('/followups/${c.followUpId}');
                }
              },
            ),
            row(Icons.bolt_rounded, s.simulateFormEnquiry, () {
              final lead = b.simulateFormEnquiry();
              notif.present(b.notifications.first);
              context.push('/leads/${lead.id}');
            }),
            row(Icons.storefront_outlined, s.simulateIndiaMartEnquiry, () {
              final lead = b.simulateIndiaMartEnquiry();
              notif.present(b.notifications.first);
              context.push('/leads/${lead.id}');
            }),
            row(
              Icons.rocket_launch_outlined,
              'Simulate campaign progress',
              () => context.push('/campaign/new'),
            ),
            row(
              Icons.hourglass_bottom_rounded,
              'Simulate trial running low',
              () {
                b.simulatePlanState(PlanStatus.trial, minutesLeft: 4);
                context.go('/home');
              },
            ),
            row(Icons.credit_card_off_outlined, 'Simulate payment due', () {
              b.simulatePlanState(PlanStatus.pastDue, minutesLeft: 0);
              context.go('/home');
            }),
          ]),
          SectionLabel(s.notifications),
          group([
            row(
              Icons.local_fire_department_outlined,
              'Hot lead notification',
              () => notif.present(
                b.simulateNotification(NotificationType.hotLead),
              ),
            ),
            row(
              Icons.chat_bubble_outline_rounded,
              'Follow-up ready notification',
              () => notif.present(
                b.simulateNotification(NotificationType.followUpReady),
              ),
            ),
            row(
              Icons.event_outlined,
              'Callback notification',
              () => notif.present(
                b.simulateNotification(NotificationType.callback),
              ),
            ),
          ]),
          SectionLabel(s.resetLabel),
          group([
            row(Icons.replay_rounded, s.replayOnboarding, () async {
              await ref.read(localPrefsProvider).reset();
              if (context.mounted) context.go('/onboarding');
            }),
          ]),
        ],
      ),
    );
  }
}

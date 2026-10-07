import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import 'campaign_progress_widgets.dart';

// ============================================================ Progress
class CampaignProgressScreen extends ConsumerWidget {
  const CampaignProgressScreen({super.key, required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(activeCampaignProvider);
    final c = live?.id == campaignId ? live : null;
    final t = Theme.of(context).textTheme;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: FutureBuilder<Campaign>(
          future: ref.read(campaignRepoProvider).get(campaignId),
          builder: (context, snap) {
            if (snap.hasData) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) =>
                    ref.read(activeCampaignProvider.notifier).set(snap.data!),
              );
            }
            if (snap.hasError) {
              return ErrorState(
                message: friendlyError(snap.error!),
                onRetry: () => context.pop(),
              );
            }
            return const SkeletonList(count: 3);
          },
        ),
      );
    }
    final s = c.stats;
    final running = c.isActive;
    final done = c.status == CampaignStatus.completed;
    final agentName = ref.watch(employeeNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign'),
        actions: [
          if (running)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Pause calling?'),
                    content: Text(
                      '$agentName will stop after the current call. Remaining leads stay in your list.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep going'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Stop',
                          style: TextStyle(color: AppColors.hot),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final stopped = await ref
                      .read(campaignRepoProvider)
                      .stop(c.id);
                  ref.read(activeCampaignProvider.notifier).set(stopped);
                }
              },
              child: const Text('Stop', style: TextStyle(color: AppColors.hot)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
        children: [
          AppCard(
            child: Column(
              children: [
                Mascot(
                  state: done
                      ? MascotState.success
                      : (running ? MascotState.calling : MascotState.welcome),
                  size: 150,
                ),
                const SizedBox(height: 10),
                Text(
                  done
                      ? '$agentName finished calling ✓'
                      : (running
                            ? '$agentName is doing the work for you'
                            : 'Campaign stopped'),
                  style: t.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  running
                      ? 'You\'ll get a notification for every hot lead.'
                      : '${s.completed} of ${s.total} leads called',
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: s.progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Column(
                    children: [
                      LinearProgressIndicator(
                        value: v,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(9),
                        backgroundColor: AppColors.brandSoft,
                        color: done ? AppColors.success : AppColors.brand,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('${(v * 100).round()}%', style: t.titleSmall),
                          const Spacer(),
                          Text('${s.remaining} remaining', style: t.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Status'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              CampaignStatTile('Queued', s.queued, AppColors.inkSoft),
              CampaignStatTile('Completed', s.completed, AppColors.ink),
              CampaignStatTile('Connected', s.connected, AppColors.success),
              CampaignStatTile(
                'Interested',
                s.interested,
                const Color(0xFFB45309),
              ),
              CampaignStatTile('🔥 Hot', s.hot, AppColors.hot),
              CampaignStatTile('Remaining', s.remaining, AppColors.brand),
            ],
          ),
          if (c.recentCallIds.isNotEmpty) ...[
            const SectionLabel('Latest results'),
            for (final id in c.recentCallIds)
              CampaignRecentCallTile(callId: id),
          ],
          if (!running) ...[
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Review follow-ups',
              icon: Icons.chat_rounded,
              color: AppColors.whatsapp,
              onPressed: () => context.go('/followups'),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'View hot leads',
              onPressed: () => context.go('/leads?filter=hot'),
            ),
          ],
        ],
      ),
    );
  }
}

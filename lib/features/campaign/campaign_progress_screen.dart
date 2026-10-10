import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'campaign_progress_widgets.dart';

// ============================================================ Progress
class CampaignProgressScreen extends ConsumerWidget {
  const CampaignProgressScreen({super.key, required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
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
                message: friendlyError(snap.error!, s),
                onRetry: () => context.pop(),
              );
            }
            return const SkeletonList(count: 3);
          },
        ),
      );
    }
    final st = c.stats;
    final running = c.isActive;
    final done = c.status == CampaignStatus.completed;
    final agentName = ref.watch(employeeNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.campaignTitle),
        actions: [
          if (running)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.hot),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(s.pauseCallingQ),
                    content: Text(s.stopsAfterCurrent(agentName)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(s.keepGoing),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.hot,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(s.stop),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  Haptics.warn();
                  final stopped = await ref
                      .read(campaignRepoProvider)
                      .stop(c.id);
                  ref.read(activeCampaignProvider.notifier).set(stopped);
                }
              },
              child: Text(s.stop),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
        children: [
          Reveal(
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  Mascot(
                    state: done
                        ? MascotState.success
                        : (running ? MascotState.calling : MascotState.welcome),
                    size: 110,
                  ),
                  const SizedBox(height: 10),
                  SwapFade(
                    child: Text(
                      done
                          ? s.finishedCalling(agentName)
                          : (running
                                ? s.isCalling(agentName)
                                : s.campaignStopped),
                      key: ValueKey('$done$running'),
                      style: t.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.leadsCalled(st.completed, st.total),
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: st.progress),
                    duration: AppMotion.of(context, AppMotion.slow),
                    curve: AppMotion.emphasized,
                    builder: (_, v, _) => Column(
                      children: [
                        LinearProgressIndicator(
                          value: v,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(9),
                          backgroundColor: AppColors.surfaceMuted,
                          color: done ? AppColors.success : AppColors.brand,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              '${(v * 100).round()}%',
                              style: t.titleSmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Text(s.nLeft(st.remaining), style: t.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Reveal(
            index: 1,
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: CampaignStatTile(
                        s.statConnected,
                        st.connected,
                        AppColors.ink,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: CampaignStatTile(
                        s.statInterested,
                        st.interested,
                        AppColors.ink,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: CampaignStatTile(s.statHot, st.hot, AppColors.hot),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (c.recentCallIds.isNotEmpty) ...[
            SectionLabel(s.latestResults),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AnimatedSize(
                duration: AppMotion.of(context, AppMotion.base),
                curve: AppMotion.standard,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    for (var i = 0; i < c.recentCallIds.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 68),
                      Reveal(
                        key: ValueKey(c.recentCallIds[i]),
                        id: 'campaign-call-${c.recentCallIds[i]}',
                        child: CampaignRecentCallTile(
                          callId: c.recentCallIds[i],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.slow),
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: running
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const SizedBox(height: 24),
                      PopIn(
                        child: PrimaryButton(
                          label: s.reviewFollowUps,
                          icon: Icons.chat_outlined,
                          onPressed: () => context.go('/followups'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: s.viewHotLeads,
                        onPressed: () => context.go('/leads?filter=hot'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

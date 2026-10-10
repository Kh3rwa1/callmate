import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../campaign/campaign_widgets.dart';
import 'home_widgets.dart';

/// Home – "What happened today?"
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final biz = ref.watch(businessProvider).value;
    final agent = ref.watch(agentProvider).value;
    final dash = ref.watch(dashboardProvider);
    final campaign = ref.watch(activeCampaignProvider);
    final unread =
        ref.watch(notificationsProvider).value?.where((n) => !n.read).length ??
        0;
    final live = (campaign != null && campaign.isActive) ? campaign : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brand,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.read(dataVersionProvider.notifier).bump();
            await ref.read(dashboardProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 14, 10, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.greeting(),
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkFaint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SwapFade(
                              child: Text(
                                biz?.name ?? s.homeWelcome,
                                key: ValueKey(biz?.name),
                                style: t.headlineSmall?.copyWith(
                                  fontSize: 26,
                                  letterSpacing: -0.6,
                                  height: 1.15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (AppEnv.showDemoTools)
                        IconButton(
                          tooltip: s.demoControls,
                          color: AppColors.inkFaint,
                          onPressed: () => context.push('/demo'),
                          icon: const Icon(Icons.science_outlined, size: 22),
                        ),
                      IconButton(
                        tooltip: unread > 0
                            ? s.newNotifications(unread)
                            : s.notifications,
                        color: AppColors.ink,
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          backgroundColor: AppColors.hotFill,
                          largeSize: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          textStyle: t.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                          offset: const Offset(5, -4),
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            size: 25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  18,
                  AppSpace.page,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Reveal(
                    id: 'home-hero',
                    index: 1,
                    child: HomeAgentCard(
                      agent: agent,
                      callsToday: dash.value?.callsToday,
                    ),
                  ),
                ),
              ),
              // The live banner grows in and out instead of popping.
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: AppMotion.of(context, AppMotion.slow),
                  curve: AppMotion.emphasized,
                  alignment: Alignment.topCenter,
                  child: live != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.page,
                            14,
                            AppSpace.page,
                            0,
                          ),
                          child: PopIn(
                            child: CampaignLiveBanner(campaign: live),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  0,
                  AppSpace.page,
                  32,
                ),
                sliver: SliverToBoxAdapter(
                  child: AsyncView<DailySummary>(
                    value: dash,
                    onRetry: () => ref.invalidate(dashboardProvider),
                    loading: const HomeSkeleton(),
                    data: (d) => _HomeBody(d: d),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.d});
  final DailySummary d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final next = ref
        .watch(callbacksProvider)
        .value
        ?.where(
          (c) =>
              c.status == CallbackStatus.scheduled &&
              c.scheduledAt.isAfter(
                DateTime.now().subtract(const Duration(hours: 1)),
              ),
        )
        .fold<Callback?>(
          null,
          (a, b) => a == null || b.scheduledAt.isBefore(a.scheduledAt) ? b : a,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _stagger([
        SectionLabel(s.todaysResults),
        HomeStatStrip(
          stats: [
            HomeStat(
              d.connected,
              s.statConnected,
              () => context.go('/calls?filter=connected'),
            ),
            HomeStat(
              d.interested,
              s.statInterested,
              () => context.go('/leads?filter=warm'),
            ),
            HomeStat(
              d.hot,
              s.statHot,
              () => context.go('/leads?filter=hot'),
              accent: AppColors.hot,
            ),
          ],
        ),
        SectionLabel(s.needsAttention),
        HomeActionGroup(
          rows: [
            if (d.hot > 0)
              HomeActionRow(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.hot,
                tint: AppColors.hotSoft,
                count: d.hot,
                label: s.hotLeadsLabel,
                onTap: () => context.go('/leads?filter=hot'),
              )
            else
              HomeActionRow(
                icon: Icons.local_fire_department_outlined,
                color: AppColors.inkFaint,
                tint: AppColors.surfaceMuted,
                label: s.noHotLeadsYet,
                trailing: s.callNewLeadsShort,
                onTap: () => context.push('/campaign/new'),
              ),
            HomeActionRow(
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.whatsapp,
              tint: AppColors.whatsappSoft,
              count: d.followUpsReady == 0 ? null : d.followUpsReady,
              label: d.followUpsReady == 0
                  ? s.allCaughtUp
                  : s.followUpsReadyLabel,
              onTap: () => context.go('/followups'),
            ),
            if (d.callbacksToday > 0 || next != null)
              HomeActionRow(
                icon: Icons.event_outlined,
                color: AppColors.info,
                tint: AppColors.infoSoft,
                count: d.callbacksToday > 0 ? d.callbacksToday : null,
                label: d.callbacksToday > 0
                    ? s.callbacksLabel(d.callbacksToday)
                    : s.upcomingCallback,
                detail: next == null
                    ? null
                    : s.nextCallback(
                        next.leadName.split(' ').first,
                        Fmt.time(next.scheduledAt),
                      ),
                onTap: () => context.push('/callbacks'),
              ),
          ],
        ),
        if (d.newLeadsReady > 0) ...[
          const SizedBox(height: 20),
          CallNewLeadsButton(count: d.newLeadsReady),
        ],
        SectionLabel(s.todaysActivity),
        HomeActivityList(
          items: d.activity.take(3).toList(),
          emptyText: s.noCallsYet,
        ),
      ]),
    );
  }
}

/// Wraps page sections in a staggered fade-and-lift entrance that plays
/// once per app session (not on every refresh or tab switch).
List<Widget> _stagger(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    Reveal(id: 'home-section-$i', index: 2 + i, child: children[i]),
];

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
import '../campaign/campaign_widgets.dart';
import '../../core/config/brand.dart';
import 'home_widgets.dart';

/// Home – "What happened today?"
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final biz = ref.watch(businessProvider).value;
    final agent = ref.watch(agentProvider).value;
    final dash = ref.watch(dashboardProvider);
    final campaign = ref.watch(activeCampaignProvider);
    final unread =
        ref.watch(notificationsProvider).value?.where((n) => !n.read).length ??
        0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
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
                              Fmt.greeting(),
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkFaint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              biz?.name ?? 'Welcome',
                              style: t.headlineSmall?.copyWith(
                                fontSize: 26,
                                letterSpacing: -0.6,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (AppEnv.showDemoTools)
                        IconButton(
                          tooltip: 'Demo controls',
                          color: AppColors.inkFaint,
                          onPressed: () => context.push('/demo'),
                          icon: const Icon(Icons.science_outlined, size: 22),
                        ),
                      IconButton(
                        tooltip: unread > 0
                            ? '$unread new notifications'
                            : 'Notifications',
                        color: AppColors.ink,
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          backgroundColor: AppColors.hot,
                          largeSize: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          textStyle: t.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
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
                    index: 1,
                    child: HomeAgentCard(
                      agent: agent,
                      callsToday: dash.value?.callsToday,
                    ),
                  ),
                ),
              ),
              if (campaign != null && campaign.isActive)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    14,
                    AppSpace.page,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: CampaignLiveBanner(campaign: campaign),
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
                    data: (d) => _HomeBody(
                      d: d,
                      agentName: agent?.name ?? Brand.employeeFallbackName,
                    ),
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

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.d, required this.agentName});
  final DailySummary d;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _stagger([
        const SectionLabel("Today's results"),
        HomeStatStrip(
          stats: [
            HomeStat(d.callsToday, 'Calls', () => context.go('/calls')),
            HomeStat(
              d.connected,
              'Connected',
              () => context.go('/calls?filter=connected'),
            ),
            HomeStat(
              d.interested,
              'Interested',
              () => context.go('/leads?filter=warm'),
            ),
            HomeStat(d.hot, 'Hot', () => context.go('/leads?filter=hot')),
          ],
        ),
        const SectionLabel('Needs your attention'),
        HomeActionGroup(
          rows: [
            if (d.hot > 0)
              HomeActionRow(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.hot,
                tint: AppColors.hotSoft,
                count: d.hot,
                label: 'hot leads',
                onTap: () => context.go('/leads?filter=hot'),
              )
            else
              HomeActionRow(
                icon: Icons.local_fire_department_outlined,
                color: AppColors.inkFaint,
                tint: AppColors.surfaceMuted,
                label: 'No hot leads yet',
                trailing: 'Call new leads',
                onTap: () => context.push('/campaign/new'),
              ),
            HomeActionRow(
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.whatsapp,
              tint: AppColors.whatsappSoft,
              count: d.followUpsReady == 0 ? null : d.followUpsReady,
              label: d.followUpsReady == 0
                  ? 'All caught up'
                  : 'follow-ups ready',
              onTap: () => context.go('/followups'),
            ),
            if (d.callbacksToday > 0)
              HomeActionRow(
                icon: Icons.event_outlined,
                color: AppColors.info,
                tint: AppColors.infoSoft,
                count: d.callbacksToday,
                label: d.callbacksToday == 1 ? 'callback' : 'callbacks',
                onTap: () => context.push('/callbacks'),
              ),
          ],
        ),
        if (d.newLeadsReady > 0) ...[
          const SizedBox(height: 20),
          CallNewLeadsButton(count: d.newLeadsReady),
        ],
        const SectionLabel("Today's AI activity"),
        HomeActivityList(
          items: d.activity.take(3).toList(),
          emptyText: 'No calls yet',
        ),
      ], from: 2),
    );
  }
}

/// Wraps page sections in a staggered fade-and-lift entrance.
List<Widget> _stagger(List<Widget> children, {int from = 0}) => [
  for (var i = 0; i < children.length; i++)
    Reveal(index: from + i, child: children[i]),
];

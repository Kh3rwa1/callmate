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
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, 8, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Fmt.greeting(),
                              style: t.bodyLarge?.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${biz?.name ?? 'Welcome'}\u00A0👋',
                              style: t.headlineSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (AppEnv.showDemoTools)
                        IconButton(
                          tooltip: 'Demo controls',
                          onPressed: () => context.push('/demo'),
                          icon: const Icon(Icons.science_outlined),
                        ),
                      IconButton(
                        tooltip: unread > 0
                            ? '$unread new notifications'
                            : 'Notifications',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          backgroundColor: AppColors.hot,
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            size: 27,
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
                      humanLabel: ref.watch(workflowProvider).humanLabel,
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
  const _HomeBody({
    required this.d,
    required this.agentName,
    required this.humanLabel,
  });
  final DailySummary d;
  final String agentName;
  final String humanLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _stagger([
        const SectionLabel("Today's results"),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.32,
          children: [
            HomeMetric(
              value: d.callsToday,
              label: 'Calls',
              icon: Icons.call_rounded,
              tint: AppColors.brandSoft,
              color: AppColors.brand,
              onTap: () => context.go('/calls'),
            ),
            HomeMetric(
              value: d.connected,
              label: 'Connected',
              icon: Icons.check_circle_rounded,
              tint: AppColors.successSoft,
              color: AppColors.success,
              onTap: () => context.go('/calls?filter=connected'),
            ),
            HomeMetric(
              value: d.interested,
              label: 'Interested',
              icon: Icons.wb_sunny_rounded,
              tint: AppColors.warmSoft,
              color: AppColors.warmInk,
              onTap: () => context.go('/leads?filter=warm'),
            ),
            HomeMetric(
              value: d.hot,
              label: 'Hot Leads',
              icon: Icons.local_fire_department_rounded,
              tint: AppColors.hotSoft,
              color: AppColors.hot,
              onTap: () => context.go('/leads?filter=hot'),
            ),
          ],
        ),
        const SectionLabel('Needs your attention'),
        if (d.hot > 0)
          HomeActionCard(
            icon: Icons.local_fire_department_rounded,
            tint: AppColors.hotSoft,
            title: '${d.hot} hot leads',
            body: 'These leads are ready for follow-up.',
            cta: 'View hot leads',
            ctaColor: AppColors.hot,
            onTap: () => context.go('/leads?filter=hot'),
          )
        else
          HomeActionCard(
            icon: Icons.auto_awesome_rounded,
            tint: AppColors.brandSoft,
            ctaColor: AppColors.brand,
            title: 'No hot leads yet',
            body: '$agentName will flag anyone ready to buy or book.',
            cta: 'Call new leads',
            onTap: () => context.push('/campaign/new'),
          ),
        if (d.callbacksToday > 0) ...[
          const SizedBox(height: 12),
          HomeActionCard(
            icon: Icons.event_rounded,
            tint: AppColors.infoSoft,
            title: '${d.callbacksToday} callbacks scheduled',
            body:
                'Customers asked to speak with your ${humanLabel.toLowerCase()}.',
            cta: 'See callbacks',
            ctaColor: AppColors.info,
            onTap: () => context.push('/callbacks'),
          ),
        ],
        const SectionLabel('Follow-ups'),
        HomeActionCard(
          icon: Icons.chat_rounded,
          tint: AppColors.whatsappSoft,
          title: d.followUpsReady == 0
              ? 'All caught up 🎉'
              : '${d.followUpsReady} follow-ups ready',
          body: d.followUpsReady == 0
              ? 'New drafts appear here after each call.'
              : '$agentName drafted them from each call. Review and send.',
          cta: d.followUpsReady == 0 ? 'View follow-ups' : 'Review & send',
          ctaColor: AppColors.whatsapp,
          onTap: () => context.go('/followups'),
        ),
        if (d.newLeadsReady > 0) ...[
          const SizedBox(height: 20),
          CallNewLeadsButton(count: d.newLeadsReady),
        ],
        const SectionLabel("Today's AI activity"),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: d.activity.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '$agentName hasn\'t made any calls yet.',
                    style: t.bodyMedium,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < d.activity.length; i++) ...[
                      if (i > 0) const Divider(indent: 64),
                      ListTile(
                        minTileHeight: 58,
                        onTap: d.activity[i].route == null
                            ? null
                            : () => context.go(d.activity[i].route!),
                        leading: IconBubble(
                          color: AppColors.surfaceMuted,
                          size: 40,
                          child: Emoji(d.activity[i].emoji, size: 18),
                        ),
                        title: Text(
                          d.activity[i].text,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          Fmt.relative(d.activity[i].at),
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../campaign/campaign_widgets.dart';
import '../../core/config/brand.dart';
import '../../core/widgets/brand_widgets.dart';

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
    final unread = ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0;

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
                            Text(Fmt.greeting(), style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                            const SizedBox(height: 2),
                            Text('${biz?.name ?? 'Welcome'}\u00A0👋', style: t.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
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
                        tooltip: unread > 0 ? '$unread new notifications' : 'Notifications',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          backgroundColor: AppColors.hot,
                          child: const Icon(Icons.notifications_none_rounded, size: 27),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 18, AppSpace.page, 0),
                sliver: SliverToBoxAdapter(
                  child: _AgentCard(agent: agent, callsToday: dash.value?.callsToday),
                ),
              ),
              if (campaign != null && campaign.isActive)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.page, 14, AppSpace.page, 0),
                  sliver: SliverToBoxAdapter(child: CampaignLiveBanner(campaign: campaign)),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
                sliver: SliverToBoxAdapter(
                  child: AsyncView<DailySummary>(
                    value: dash,
                    onRetry: () => ref.invalidate(dashboardProvider),
                    loading: const _HomeSkeleton(),
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

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.callsToday});
  final Agent? agent;
  final int? callsToday;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = agent?.status == AgentStatus.active;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 18, 12),
      semanticLabel: '${agent?.name ?? Brand.employeeFallbackName}, ${agent?.role ?? ''}, ${active ? 'active' : 'paused'}',
      onTap: () => context.go('/agent'),
      child: Row(
        children: [
          EmployeeMascot(state: active ? MascotState.calling : MascotState.welcome, size: 104, animate: active, agent: agent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent?.name ?? Brand.employeeFallbackName, style: t.titleLarge),
                Text(agent?.role ?? Brand.employeeNoun, style: t.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusDot(
                      label: active ? 'Active' : (agent?.status.label ?? 'Paused'),
                      color: active ? AppColors.success : AppColors.cold,
                      pulse: active,
                    ),
                    const SizedBox(width: 10),
                    if (callsToday != null)
                      Flexible(
                        child: Text(
                          '${Fmt.number(callsToday!)} calls today',
                          style: t.labelMedium?.copyWith(color: AppColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('View Agent →', style: t.labelMedium?.copyWith(color: AppColors.brand, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.d, required this.agentName, required this.humanLabel});
  final DailySummary d;
  final String agentName;
  final String humanLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel("Today's results"),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: [
            _Metric(value: d.callsToday, label: 'Calls', emoji: '📞', onTap: () => context.go('/calls')),
            _Metric(
              value: d.connected,
              label: 'Connected',
              emoji: '✅',
              color: AppColors.success,
              onTap: () => context.go('/calls?filter=connected'),
            ),
            _Metric(
              value: d.interested,
              label: 'Interested',
              emoji: '☀️',
              color: const Color(0xFFB45309),
              onTap: () => context.go('/leads?filter=warm'),
            ),
            _Metric(value: d.hot, label: 'Hot Leads', emoji: '🔥', color: AppColors.hot, onTap: () => context.go('/leads?filter=hot')),
          ],
        ),
        const SectionLabel('Needs your attention'),
        if (d.hot > 0)
          _ActionCard(
            emoji: '🔥',
            tint: AppColors.hotSoft,
            title: '${d.hot} hot leads',
            body: 'These leads are ready for follow-up.',
            cta: 'View hot leads',
            ctaColor: AppColors.hot,
            onTap: () => context.go('/leads?filter=hot'),
          )
        else
          _ActionCard(
            emoji: '✨',
            tint: AppColors.surfaceMuted,
            title: 'No hot leads yet',
            body: '$agentName will flag anyone ready to join.',
            cta: 'Call new leads',
            onTap: () => context.push('/campaign/new'),
          ),
        if (d.callbacksToday > 0) ...[
          const SizedBox(height: 12),
          _ActionCard(
            emoji: '📅',
            tint: AppColors.infoSoft,
            title: '${d.callbacksToday} callbacks scheduled',
            body: 'Customers asked to speak with your ${humanLabel.toLowerCase()}.',
            cta: 'See callbacks',
            ctaColor: AppColors.info,
            onTap: () => context.push('/callbacks'),
          ),
        ],
        const SectionLabel('Follow-ups'),
        _ActionCard(
          emoji: '💬',
          tint: AppColors.whatsappSoft,
          title: d.followUpsReady == 0 ? 'All caught up 🎉' : '${d.followUpsReady} follow-ups ready',
          body: d.followUpsReady == 0
              ? 'New drafts appear here after each call.'
              : '$agentName drafted them from each call. Review and send.',
          cta: d.followUpsReady == 0 ? 'View follow-ups' : 'Review & send',
          ctaColor: AppColors.whatsapp,
          onTap: () => context.go('/followups'),
        ),
        if (d.newLeadsReady > 0) ...[const SizedBox(height: 20), CallNewLeadsButton(count: d.newLeadsReady)],
        const SectionLabel("Today's AI activity"),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: d.activity.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('$agentName hasn\'t made any calls yet.', style: t.bodyMedium),
                )
              : Column(
                  children: [
                    for (var i = 0; i < d.activity.length; i++) ...[
                      if (i > 0) const Divider(indent: 64),
                      ListTile(
                        minTileHeight: 58,
                        onTap: d.activity[i].route == null ? null : () => context.go(d.activity[i].route!),
                        leading: IconBubble(color: AppColors.surfaceMuted, size: 40, child: Emoji(d.activity[i].emoji, size: 18)),
                        title: Text(d.activity[i].text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        trailing: Text(Fmt.relative(d.activity[i].at), style: t.bodySmall),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.emoji, this.color = AppColors.ink, required this.onTap});
  final int value;
  final String label;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      semanticLabel: '$value $label',
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Emoji(emoji, size: 16),
                const SizedBox(width: 6),
                Text(label, style: t.labelMedium),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkFaint),
              ],
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(Fmt.number(v.round()), style: t.displaySmall?.copyWith(color: color, fontSize: 36)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.emoji,
    required this.tint,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.ctaColor = AppColors.ink,
  });
  final String emoji;
  final Color tint;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;
  final Color ctaColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(color: tint, size: 52, child: Emoji(emoji, size: 24)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: t.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(cta, style: t.labelLarge?.copyWith(color: ctaColor, fontSize: 15)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: ctaColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SectionLabel("Today's results"),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: List.generate(
          4,
          (_) => const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Skeleton(height: 12, width: 70), Spacer(), Skeleton(height: 30, width: 60)],
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      const SkeletonCard(lines: 2),
      const SizedBox(height: 12),
      const SkeletonCard(lines: 2),
    ],
  );
}

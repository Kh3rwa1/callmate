import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'getting_started.dart';
import 'home_widgets.dart';
import 'home_hero.dart';
import 'results_card.dart';
import 'week_funnel.dart';
import '../../core/widgets/brand_widgets.dart';
import '../usage/plan_banner.dart';

/// Home – "What happened today?"
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final biz = ref.watch(businessProvider).value;
    final dash = ref.watch(dashboardProvider);
    final unread =
        ref.watch(notificationsProvider).value?.where((n) => !n.read).length ??
        0;

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
                            // Up to two lines, never cut short: the name
                            // tops out at 1.5× so a typical 20-letter name
                            // fits even at the biggest text size.
                            MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.5,
                              child: SwapFade(
                                child: GradientText(
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
                      TopBarAction(
                        key: const Key('home-help'),
                        icon: const AppGlyph(AppGlyphs.help, size: 26),
                        label: s.help,
                        onTap: () => showHelpSheet(context),
                      ),
                      TopBarAction(
                        key: const Key('home-alerts'),
                        semanticsLabel: unread > 0
                            ? s.newNotifications(unread)
                            : s.notifications,
                        label: s.alertsShort,
                        onTap: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          backgroundColor: AppColors.hotFill,
                          largeSize: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          textStyle: t.labelSmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                          offset: const Offset(5, -4),
                          child: const AppGlyph(AppGlyphs.alerts, size: 26),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.lg,
                  AppSpace.page,
                  0,
                ),
                sliver: const SliverToBoxAdapter(
                  child: Reveal(
                    id: 'home-hero',
                    index: 1,
                    child: HomeHeroCard(),
                  ),
                ),
              ),
              // New owners: three first steps, ticked from real data.
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.page),
                sliver: SliverToBoxAdapter(child: GettingStartedCard()),
              ),
              // Payment due / trial running low.
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: AppMotion.of(context, AppMotion.slow),
                  curve: AppMotion.emphasized,
                  alignment: Alignment.topCenter,
                  child: const PlanBanner(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.page,
                      14,
                      AppSpace.page,
                      0,
                    ),
                  ),
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
    final heroCallsNew =
        ref.watch(activeCampaignProvider)?.isActive != true &&
        d.hot == 0 &&
        d.followUpsReady == 0 &&
        d.leads > 0 &&
        d.newLeadsReady > 0;
    final results = ref.watch(weekResultsProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _stagger([
        if (results != null && !results.hasCalls) ...[
          SectionLabel(s.resultsThisWeek),
          const HearYourAiCard(),
        ] else
          const WeekFunnelSection(),
        SectionLabel(s.needsAttention),
        HomeActionGroup(
          rows: [
            if (d.hot > 0)
              HomeActionRow(
                glyph: AppGlyphs.hot,
                color: AppColors.hot,
                tint: AppColors.hotSoft,
                count: d.hot,
                label: s.hotLeadsLabel,
                onTap: () => context.go('/leads?filter=hot'),
              )
            else
              HomeActionRow(
                glyph: AppGlyphs.hot,
                color: AppColors.inkFaint,
                tint: AppColors.surfaceMuted,
                label: s.noHotLeadsYet,
                trailing: s.callNewLeadsShort,
                onTap: () => context.push('/campaign/new'),
              ),
            HomeActionRow(
              glyph: AppGlyphs.message,
              color: AppColors.whatsapp,
              tint: AppColors.whatsappSoft,
              count: d.followUpsReady == 0 ? null : d.followUpsReady,
              label: d.followUpsReady == 0
                  ? s.allCaughtUp
                  : s.followUpsReadyLabel,
              onTap: () => context.go('/followups'),
            ),
            HomeActionRow(
              glyph: AppGlyphs.callback,
              color: AppColors.info,
              tint: AppColors.infoSoft,
              count: d.callbacksToday > 0 ? d.callbacksToday : null,
              label: d.callbacksToday > 0
                  ? s.callbacksLabel(d.callbacksToday)
                  : next != null
                  ? s.upcomingCallback
                  : s.callbacksTitle,
              detail: next == null
                  ? null
                  : s.nextCallback(
                      next.leadName.split(' ').first,
                      Fmt.time(next.scheduledAt),
                    ),
              onTap: () => context.push('/callbacks'),
            ),
            // The hero already offers this when it's the top job.
            if (d.newLeadsReady > 0 && !heroCallsNew)
              HomeActionRow(
                glyph: AppGlyphs.call,
                color: AppColors.brand,
                tint: AppColors.brandSoft,
                label: s.callNewLeadsCount(d.newLeadsReady),
                onTap: () => context.push('/campaign/new'),
              ),
          ],
        ),
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

/// Icon with a word under it, for the Home top bar (Help, Alerts): owners
/// shouldn't have to guess what a bare icon does.
class TopBarAction extends StatelessWidget {
  const TopBarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });
  final Widget icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          // Narrow and capped so the business name, not these, gets the
          // room at big text sizes.
          constraints: const BoxConstraints(
            minWidth: 48,
            maxWidth: 64,
            minHeight: 56,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(color: AppColors.ink),
                  child: icon,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.3),
                    style: t.labelMedium?.copyWith(
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

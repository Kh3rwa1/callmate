import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/world.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// What the hero is mainly saying, in priority order.
enum HeroFocus { live, hot, resting, ready }

/// The one thing the hero asks the owner to do.
enum HeroAction {
  seeLive(AppGlyphs.call),
  seeReady(AppGlyphs.hot),
  sendMessages(AppGlyphs.message),
  callNew(AppGlyphs.call),
  addCustomers(AppGlyphs.add);

  const HeroAction(this.glyph);
  final AppGlyphs glyph;
}

/// Everything the hero shows, worked out from plain numbers so it can be
/// unit tested without widgets.
@immutable
class HeroFocusl {
  const HeroFocusl({
    required this.mode,
    required this.mascot,
    required this.status,
    required this.action,
    required this.actionLabel,
  });

  final HeroFocus mode;
  final MascotState mascot;

  /// The live status line ("Calling Ravi…", "3 ready to buy", …).
  final String status;
  final HeroAction action;
  final String actionLabel;

  /// Priority: a live call beats hot leads beats resting beats ready.
  factory HeroFocusl.from({
    required S s,
    required DateTime now,
    bool live = false,
    String? liveName,
    int hot = 0,
    int callingStart = 10,
    int callingEnd = 19,
    int followUps = 0,
    int newLeads = 0,
    int leads = 0,
  }) {
    final inHours = now.hour >= callingStart && now.hour < callingEnd;
    final HeroFocus mode;
    final MascotState mascot;
    final String status;
    if (live) {
      mode = HeroFocus.live;
      mascot = MascotState.calling;
      status = liveName == null || liveName.trim().isEmpty
          ? s.heroCallingAny
          : s.heroCalling(liveName.trim().split(' ').first);
    } else if (hot > 0) {
      mode = HeroFocus.hot;
      mascot = MascotState.waving;
      status = s.heroHot(hot);
    } else if (!inHours) {
      mode = HeroFocus.resting;
      mascot = MascotState.resting;
      status = s.heroResting(
        Fmt.time(DateTime(now.year, now.month, now.day, callingStart)),
      );
    } else {
      mode = HeroFocus.ready;
      mascot = MascotState.idle;
      status = s.heroReady;
    }

    final HeroAction action;
    if (live) {
      action = HeroAction.seeLive;
    } else if (hot > 0) {
      action = HeroAction.seeReady;
    } else if (followUps > 0) {
      action = HeroAction.sendMessages;
    } else if (leads > 0 && newLeads > 0) {
      action = HeroAction.callNew;
    } else {
      action = HeroAction.addCustomers;
    }
    final label = switch (action) {
      HeroAction.seeLive => s.heroSeeLive,
      HeroAction.seeReady => s.heroSeeReady,
      HeroAction.sendMessages => s.heroSendMessages(followUps),
      HeroAction.callNew => s.callNewLeadsCount(newLeads),
      HeroAction.addCustomers => s.heroAddCustomers,
    };
    return HeroFocusl(
      mode: mode,
      mascot: mascot,
      status: status,
      action: action,
      actionLabel: label,
    );
  }
}

/// First name of the customer being called right now, if the backend says
/// a call is ringing or connected. Only asked while a campaign is live.
final liveCallNameProvider = FutureProvider<String?>((ref) async {
  ref.watch(dataVersionProvider);
  final campaign = ref.watch(activeCampaignProvider);
  if (campaign == null || !campaign.isActive) return null;
  try {
    final page = await ref.watch(callRepoProvider).list(limit: 10);
    for (final c in page.items) {
      if (c.status == CallStatus.ringing || c.status == CallStatus.inProgress) {
        return c.leadName;
      }
    }
  } catch (_) {}
  return null;
});

/// Home hero: "Your employee today". Sits inside Home's cobalt world: the
/// mascot (whose pose follows what is happening), one live status line,
/// today's call count as a poster-sized number and the single most
/// important thing to do next.
class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final agent = ref.watch(agentProvider).value;
    final dash = ref.watch(dashboardProvider).value;
    final campaign = ref.watch(activeCampaignProvider);
    final live = campaign != null && campaign.isActive;
    final model = HeroFocusl.from(
      s: s,
      now: ref.watch(clockProvider)(),
      live: live,
      liveName: live ? ref.watch(liveCallNameProvider).value : null,
      hot: dash?.hot ?? 0,
      callingStart: agent?.callingHoursStart ?? 10,
      callingEnd: agent?.callingHoursEnd ?? 19,
      followUps: dash?.followUpsReady ?? 0,
      newLeads: dash?.newLeadsReady ?? 0,
      leads: dash?.leads ?? 0,
    );
    return HeroView(
      model: model,
      employeeName: s.employeeName(agent?.name),
      callsToday: dash?.callsToday,
      onOpenEmployee: () => context.go('/agent'),
      onAction: () => switch (model.action) {
        HeroAction.seeLive => context.push('/campaigns/${campaign!.id}'),
        HeroAction.seeReady => context.go('/leads?filter=hot'),
        HeroAction.sendMessages => context.go('/followups'),
        HeroAction.callNew => context.push('/campaign/new'),
        // The add screen offers contacts first, plus typing one or a file,
        // so saying "Not now" to contacts isn't a dead end.
        HeroAction.addCustomers => context.push('/leads/import'),
      },
    );
  }
}

/// The hero's look, separate from data so every state can be tested.
class HeroView extends StatelessWidget {
  const HeroView({
    super.key,
    required this.model,
    required this.employeeName,
    required this.callsToday,
    required this.onAction,
    this.onOpenEmployee,
  });

  final HeroFocusl model;
  final String employeeName;
  final int? callsToday;
  final VoidCallback onAction;
  final VoidCallback? onOpenEmployee;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    const world = AppWorld.home;
    final live = model.mode == HeroFocus.live;
    return Column(
      key: const Key('home-hero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One poster number with the bird beside it, one line saying
        // what matters, one button. Riya's name lives on her own tab.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: BigStat(
                countKey: const Key('hero-calls'),
                value: callsToday,
                label: s.callsToday,
                color: world.fg,
                labelColor: world.soft,
                size: 96,
                countUp: true,
                semanticsLabel: callsToday == null
                    ? null
                    : '${Fmt.number(callsToday!)} ${s.callsToday}',
              ),
            ),
            Semantics(
              button: onOpenEmployee != null,
              label: employeeName,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenEmployee,
                child: SwapFade(
                  child: Mascot(
                    key: ValueKey(model.mascot),
                    state: model.mascot,
                    size: 72,
                    haloColor: Colors.white.withValues(alpha: 0.12),
                    semanticLabel: employeeName,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SwapFade(
            child: _StatusLine(
              key: ValueKey(model.status),
              text: model.status,
              live: live,
              hot: model.mode == HeroFocus.hot,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        WorldButton(
          key: const Key('hero-action'),
          world: world,
          label: model.actionLabel,
          iconWidget: AppGlyph(model.action.glyph),
          onPressed: onAction,
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    super.key,
    required this.text,
    required this.live,
    required this.hot,
  });
  final String text;
  final bool live;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = t.bodyLarge?.copyWith(
      color: hot ? AppWorld.home.cta : AppWorld.home.fg,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    if (!live) {
      return Text(text, key: const Key('hero-status'), style: style);
    }
    return Row(
      children: [
        StatusDot(label: '', color: AppColors.liveDot, textColor: Colors.white),
        Expanded(
          child: Text(text, key: const Key('hero-status'), style: style),
        ),
      ],
    );
  }
}

import '../../core/widgets/employee_avatar.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Hero card: the AI employee, live. Deep indigo surface, mascot on the
/// right, one big number that counts up the first time it appears.
class HomeAgentCard extends StatelessWidget {
  const HomeAgentCard({
    super.key,
    required this.agent,
    required this.callsToday,
  });
  final Agent? agent;
  final int? callsToday;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final active = agent?.status == AgentStatus.active;
    final name = s.employeeName(agent?.name);
    const onBrand = Colors.white;
    final faint = onBrand.withValues(alpha: 0.78);
    final status = active
        ? s.active
        : s.agentStatus(agent?.status ?? AgentStatus.paused);
    return Semantics(
      button: true,
      label: s.heroSemantics(
        name,
        s.data(agent?.role ?? ''),
        status,
        callsToday,
      ),
      excludeSemantics: true,
      child: Pressable(
        onTap: () => context.go('/agent'),
        scale: 0.975,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card + 6),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.heroGradient,
              stops: [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF0038C8,
                ).withValues(alpha: AppColors.isDark ? 0.45 : 0.2),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card + 6),
            child: Stack(
              children: [
                // Soft light for depth.
                const Positioned(
                  right: -30,
                  top: -60,
                  child: _Glow(size: 220, alpha: 0.20),
                ),
                const Positioned(
                  left: -60,
                  bottom: -90,
                  child: _Glow(size: 200, alpha: 0.08),
                ),
                Positioned(
                  right: 26,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AgentAvatar(
                      agent: agent,
                      size: 84,
                      onDark: true,
                      activity: active
                          ? EmployeeActivity.calling
                          : EmployeeActivity.idle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 140, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: _LiveChip(label: status, live: active),
                          ),
                          const SizedBox(width: 10),
                          if (active) const VoiceWave(height: 14),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: t.titleLarge?.copyWith(
                          color: onBrand,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 18),
                      SwapFade(
                        child: callsToday == null
                            ? Text(
                                '–',
                                key: const ValueKey('none'),
                                style: t.displaySmall?.copyWith(
                                  color: onBrand,
                                  fontSize: 46,
                                  height: 1,
                                ),
                              )
                            : AnimatedCount(
                                key: const ValueKey('count'),
                                value: callsToday!,
                                countUp: true,
                                format: Fmt.number,
                                style: t.displaySmall?.copyWith(
                                  color: onBrand,
                                  fontSize: 46,
                                  height: 1,
                                  letterSpacing: -1.5,
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.callsToday,
                        style: t.labelMedium?.copyWith(color: faint),
                      ),
                    ],
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

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});
  final double size;
  final double alpha;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// Status pill on the hero card: white text (always readable on indigo),
/// a green pulsing dot while live.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.label, required this.live});
  final String label;
  final bool live;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: StatusDot(
      label: label,
      color: live ? AppColors.liveDot : Colors.white70,
      textColor: Colors.white,
      pulse: live,
    ),
  );
}

/// Five bars that bob like a voice meter while the employee is live.
class VoiceWave extends StatefulWidget {
  const VoiceWave({super.key, this.color = Colors.white, this.height = 16});
  final Color color;
  final double height;
  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++)
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height:
                    widget.height *
                    (0.3 +
                        0.7 *
                            (0.5 +
                                    0.5 *
                                        math.sin(
                                          (_c.value * 2 * math.pi) + i * 1.3,
                                        ))
                                .abs()),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One value in [HomeStatStrip].
class HomeStat {
  const HomeStat(this.value, this.label, this.onTap, {this.accent});
  final int value;
  final String label;
  final VoidCallback onTap;

  /// Colour for the number (e.g. hot); defaults to ink.
  final Color? accent;
}

/// Today's numbers: one card, big figures that count up, quiet labels,
/// hairline dividers.
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({super.key, required this.stats});
  final List<HomeStat> stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 14,
                  endIndent: 14,
                  color: AppColors.border,
                ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${stats[i].value} ${stats[i].label}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: stats[i].onTap,
                    borderRadius: BorderRadius.circular(AppRadius.cardSm),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedCount(
                            value: stats[i].value,
                            countUp: true,
                            format: Fmt.number,
                            style: t.headlineMedium?.copyWith(
                              color: stats[i].accent ?? AppColors.ink,
                              fontSize: 27,
                              height: 1.1,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stats[i].label,
                            textAlign: TextAlign.center,
                            style: t.labelSmall?.copyWith(
                              color: AppColors.inkFaint,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grouped card of compact action rows separated by hairlines.
class HomeActionGroup extends StatelessWidget {
  const HomeActionGroup({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: AnimatedSize(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66, endIndent: 16),
            rows[i],
          ],
        ],
      ),
    ),
  );
}

/// "[icon]  12 hot leads  ›" – count bold, label soft, no sentences. An
/// optional [detail] line sits underneath (e.g. the next callback).
class HomeActionRow extends StatelessWidget {
  const HomeActionRow({
    super.key,
    required this.icon,
    required this.color,
    required this.tint,
    required this.label,
    required this.onTap,
    this.count,
    this.trailing,
    this.detail,
  });
  final IconData icon;
  final Color color;
  final Color tint;
  final int? count;
  final String label;
  final String? trailing;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final strong = t.titleMedium?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w800,
    );
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (count != null)
                            TextSpan(
                              text: '${Fmt.number(count!)} ',
                              style: strong,
                            ),
                          TextSpan(
                            text: label,
                            style: count == null
                                ? strong
                                : t.titleMedium?.copyWith(
                                    color: AppColors.inkSoft,
                                    fontWeight: FontWeight.w600,
                                  ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    trailing!,
                    style: t.labelMedium?.copyWith(color: AppColors.brand),
                  ),
                ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact one-line timeline: icon · text · faint time.
class HomeActivityList extends StatelessWidget {
  const HomeActivityList({
    super.key,
    required this.items,
    required this.emptyText,
  });
  final List<ActivityItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Text(emptyText, style: t.bodyMedium),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final a in items)
            InkWell(
              onTap: a.route == null ? null : () => context.go(a.route!),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
                child: Row(
                  children: [
                    Emoji(a.emoji, size: 18, color: AppColors.inkSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        a.text,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      s.relative(a.at),
                      style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.s.loading,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 32),
        Skeleton(height: 18, width: 120),
        SizedBox(height: 14),
        AppCard(
          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          child: Row(
            children: [
              Expanded(child: _StatBone()),
              Expanded(child: _StatBone()),
              Expanded(child: _StatBone()),
              Expanded(child: _StatBone()),
            ],
          ),
        ),
        SizedBox(height: 32),
        Skeleton(height: 18, width: 160),
        SizedBox(height: 14),
        SkeletonCard(lines: 1),
      ],
    ),
  );
}

class _StatBone extends StatelessWidget {
  const _StatBone();
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Skeleton(height: 26, width: 40),
      SizedBox(height: 8),
      Skeleton(height: 10, width: 52),
    ],
  );
}

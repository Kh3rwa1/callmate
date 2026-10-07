import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../core/config/brand.dart';
import '../../core/widgets/brand_widgets.dart';

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
    final t = Theme.of(context).textTheme;
    final active = agent?.status == AgentStatus.active;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 18, 12),
      semanticLabel:
          '${agent?.name ?? Brand.employeeFallbackName}, ${agent?.role ?? ''}, ${active ? 'active' : 'paused'}',
      onTap: () => context.go('/agent'),
      child: Row(
        children: [
          EmployeeMascot(
            state: active ? MascotState.calling : MascotState.welcome,
            size: 104,
            animate: active,
            agent: agent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent?.name ?? Brand.employeeFallbackName,
                  style: t.titleLarge,
                ),
                Text(agent?.role ?? Brand.employeeNoun, style: t.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusDot(
                      label: active
                          ? 'Active'
                          : (agent?.status.label ?? 'Paused'),
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
                Text(
                  'View Agent →',
                  style: t.labelMedium?.copyWith(
                    color: AppColors.brand,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeMetric extends StatelessWidget {
  const HomeMetric({
    super.key,
    required this.value,
    required this.label,
    required this.emoji,
    this.color = AppColors.ink,
    required this.onTap,
  });
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
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.number(v.round()),
                  style: t.displaySmall?.copyWith(color: color, fontSize: 36),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeActionCard extends StatelessWidget {
  const HomeActionCard({
    super.key,
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
                    Text(
                      cta,
                      style: t.labelLarge?.copyWith(
                        color: ctaColor,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: ctaColor,
                    ),
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

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});
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
              children: [
                Skeleton(height: 12, width: 70),
                Spacer(),
                Skeleton(height: 30, width: 60),
              ],
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

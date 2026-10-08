import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../core/config/brand.dart';
import '../../core/widgets/brand_widgets.dart';

/// Hero card: the AI employee, live. Gradient surface, breathing mascot,
/// a voice waveform while she's working.
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
    const onBrand = Colors.white;
    return Semantics(
      button: true,
      label:
          '${agent?.name ?? Brand.employeeFallbackName}, ${agent?.role ?? ''}, ${active ? 'active' : 'paused'}',
      child: Pressable(
        onTap: () => context.go('/agent'),
        scale: 0.975,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card + 4),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4F46E5), Color(0xFF6D28D9)],
            ),
            boxShadow: AppShadows.glow(AppColors.brand),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card + 4),
            child: Stack(
              children: [
                // Soft light blobs for depth.
                const Positioned(
                  right: -40,
                  top: -50,
                  child: _Glow(size: 180, alpha: 0.18),
                ),
                const Positioned(
                  left: 60,
                  bottom: -70,
                  child: _Glow(size: 160, alpha: 0.10),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 18, 16),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        EmployeeMascot(
                          state: active
                              ? MascotState.calling
                              : MascotState.welcome,
                          size: 100,
                          animate: active,
                          agent: agent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agent?.name ?? Brand.employeeFallbackName,
                                style: t.titleLarge?.copyWith(color: onBrand),
                              ),
                              Text(
                                agent?.role ?? Brand.employeeNoun,
                                style: t.bodyMedium?.copyWith(
                                  color: onBrand.withValues(alpha: 0.82),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _LiveChip(
                                    label: active
                                        ? 'Active'
                                        : (agent?.status.label ?? 'Paused'),
                                    live: active,
                                  ),
                                  const SizedBox(width: 10),
                                  if (active) const VoiceWave(),
                                ],
                              ),
                              if (callsToday != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    AnimatedCount(
                                      value: callsToday!,
                                      format: Fmt.number,
                                      style: t.titleMedium?.copyWith(
                                        color: onBrand,
                                      ),
                                    ),
                                    Text(
                                      ' calls today',
                                      style: t.bodyMedium?.copyWith(
                                        color: onBrand.withValues(alpha: 0.82),
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                      color: onBrand.withValues(alpha: 0.9),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.label, required this.live});
  final String label;
  final bool live;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(99),
    ),
    child: StatusDot(
      label: label,
      color: live ? const Color(0xFF86EFAC) : Colors.white70,
      pulse: live,
    ),
  );
}

/// Five bars that bob like a voice meter. Pure decoration.
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

class HomeMetric extends StatelessWidget {
  const HomeMetric({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.color = AppColors.ink,
    this.tint = AppColors.surfaceMuted,
    required this.onTap,
  });
  final int value;
  final String label;
  final IconData icon;
  final Color color;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      semanticLabel: '$value $label',
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: AnimatedCount(
                    value: value,
                    format: Fmt.number,
                    style: t.headlineMedium?.copyWith(
                      color: AppColors.ink,
                      fontSize: 30,
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: t.labelMedium),
              ],
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
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.ctaColor = AppColors.ink,
  });
  final IconData icon;
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
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: ctaColor, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 3),
                Text(body, style: t.bodyMedium?.copyWith(fontSize: 14)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      cta,
                      style: t.labelLarge?.copyWith(
                        color: ctaColor,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
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

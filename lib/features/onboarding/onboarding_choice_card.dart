import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Two equal-height columns of [OnboardingChoiceCard]s that pop in one
/// after another. Rows grow with their text (long Hindi/Bengali labels
/// wrap instead of shrinking).
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({super.key, required this.children, this.startDelay});
  final List<Widget> children;

  /// When the first card pops (after the title has started to arrive).
  final Duration? startDelay;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    final start = startDelay ?? const Duration(milliseconds: 120);
    Widget cell(int i) => i < children.length
        ? PopIn(
            delay: start + Duration(milliseconds: 45 * i),
            duration: const Duration(milliseconds: 480),
            child: children[i],
          )
        : const SizedBox.shrink();
    return Column(
      children: [
        for (var r = 0; r < children.length; r += 2) ...[
          if (r > 0) const SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell(r)),
                const SizedBox(width: gap),
                Expanded(child: cell(r + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Selectable card used by the business-type and skills steps.
///
/// Press: springs down. Select: border and fill crossfade, the icon tile
/// turns brand and bounces, and a tick draws itself in the corner.
class OnboardingChoiceCard extends StatefulWidget {
  const OnboardingChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multi = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  State<OnboardingChoiceCard> createState() => _OnboardingChoiceCardState();
}

class _OnboardingChoiceCardState extends State<OnboardingChoiceCard>
    with TickerProviderStateMixin {
  // Icon bounce: a spring kicked with velocity, settling back at 0.
  late final AnimationController _bounce = AnimationController.unbounded(
    vsync: this,
  );
  // Tick: 0 = empty box/circle, 1 = filled with a drawn check.
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(OnboardingChoiceCard old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    if (AppMotion.reduced(context)) {
      _tick.value = widget.selected ? 1 : 0;
      return;
    }
    if (widget.selected) {
      _tick.forward();
      _bounce.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 420,
            ratio: 0.32,
          ),
          0,
          0,
          5,
        ),
      );
    } else {
      _tick.reverse();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final selected = widget.selected;
    const d = Duration(milliseconds: 220);
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: Pressable(
          scale: 0.95,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: d,
            curve: AppMotion.standard,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.cardSm),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _bounce,
                      builder: (_, child) => Transform.scale(
                        scale: 1 + _bounce.value.clamp(-0.3, 0.4),
                        child: child,
                      ),
                      child: AnimatedContainer(
                        duration: d,
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.brandFill
                              : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(
                            end: selected ? Colors.white : AppColors.ink,
                          ),
                          duration: d,
                          builder: (_, c, _) =>
                              Icon(widget.icon, size: 28, color: c),
                        ),
                      ),
                    ),
                    const Spacer(),
                    ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: _tick,
                        builder: (_, _) => CustomPaint(
                          size: const Size.square(22),
                          painter: _TickPainter(
                            progress: _tick.value,
                            square: widget.multi,
                            fill: AppColors.brandFill,
                            border: AppColors.border,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  style: t.titleMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: t.bodySmall?.copyWith(
                      fontSize: 13,
                      color: AppColors.inkFaint,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Radio circle (or checkbox square) that fills, then draws a check.
class _TickPainter extends CustomPainter {
  _TickPainter({
    required this.progress,
    required this.square,
    required this.fill,
    required this.border,
  });
  final double progress;
  final bool square;
  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1),
      Radius.circular(square ? 6 : w / 2),
    );
    // Fill grows from the centre during the first half.
    final grow = Curves.easeOutBack.transform(
      (progress / 0.55).clamp(0.0, 1.0),
    );
    if (grow < 1) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
    if (grow > 0) {
      canvas.save();
      canvas.translate(w / 2, w / 2);
      canvas.scale(math.max(0, grow));
      canvas.translate(-w / 2, -w / 2);
      canvas.drawRRect(rrect, Paint()..color = fill);
      canvas.restore();
    }
    // Check draws during the second half.
    final draw = Curves.easeOutCubic.transform(
      ((progress - 0.4) / 0.6).clamp(0.0, 1.0),
    );
    if (draw <= 0) return;
    final path = Path()
      ..moveTo(w * 0.28, w * 0.53)
      ..lineTo(w * 0.44, w * 0.68)
      ..lineTo(w * 0.73, w * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.progress != progress ||
      old.square != square ||
      old.fill != fill ||
      old.border != border;
}

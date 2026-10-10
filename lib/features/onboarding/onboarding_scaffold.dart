import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../../core/widgets/brand_widgets.dart';

/// Shared onboarding frame: progress, back, scrollable body, sticky CTA.
///
/// Motion: the progress bar is a [Hero], so it stays put while the step
/// slides in under it and its fill springs forward (or back) to the new
/// step. The title, subtitle and each child then cascade in.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.children,
    required this.cta,
    this.total = 6,
    this.secondary,
    this.revealChildren = true,
  });

  final int step;
  final int total;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget cta;
  final Widget? secondary;

  /// Wrap each child in its own [Reveal]. Turn off when a screen staggers
  /// its own pieces (a form's fields, a grid's cards).
  final bool revealChildren;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final canPop = context.canPop();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: canPop
                        ? IconButton(
                            tooltip: s.back,
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: OnboardingProgress(step: step, total: total),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  24,
                  AppSpace.page,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Reveal(
                      child: Semantics(
                        header: true,
                        child: GradientText(title, style: t.headlineMedium),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Reveal(
                        index: 1,
                        child: Text(
                          subtitle!,
                          style: t.bodyLarge?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    for (var i = 0; i < children.length; i++)
                      revealChildren
                          ? Reveal(index: 2 + i, child: children[i])
                          : children[i],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                12,
                AppSpace.page,
                16,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cta,
                  if (secondary != null) ...[
                    const SizedBox(height: 4),
                    secondary!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _progressHeroTag = 'onboarding-progress';

/// "▬▬▬▭▭▭ 3/6". Shared between steps as a [Hero]: during a step change
/// the flight interpolates the fill with a springy overshoot.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.step,
    required this.total,
  });
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    // The very first show (arriving from Welcome, no hero to fly from)
    // fills from empty; afterwards the hero flight does the animating.
    const introId = 'onboarding-progress-intro';
    final intro = step == 1 && !RevealMemory.seen(introId);
    if (intro) RevealMemory.mark(introId);
    return Semantics(
      label: context.s.obStepOf(step, total),
      child: ExcludeSemantics(
        child: Hero(
          tag: _progressHeroTag,
          flightShuttleBuilder: _shuttle,
          child: _ProgressBar(
            value: step.toDouble(),
            total: total,
            intro: intro,
          ),
        ),
      ),
    );
  }

  static Widget _shuttle(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = (fromContext.widget as Hero).child as _ProgressBar;
    final to = (toContext.widget as Hero).child as _ProgressBar;
    // The flight animation runs 0→1 on push and 1→0 on pop; at 1 the later
    // (pushed) step is showing.
    final push = direction == HeroFlightDirection.push;
    final lo = push ? from : to;
    final hi = push ? to : from;
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, _) {
          final raw = animation.value.clamp(0.0, 1.0);
          final t = AppMotion.pop.transform(raw);
          return _ProgressBar(
            value: lo.value + (hi.value - lo.value) * t,
            total: hi.total,
            label: (raw > 0.5 ? hi : lo).value.round(),
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.total,
    this.intro = false,
    this.label,
  });

  /// Steps completed; fractional mid-flight.
  final double value;
  final int total;
  final bool intro;

  /// Step number shown; defaults to [value].
  final int? label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget track(double v) => _Track(fraction: v / total);
    return Row(
      children: [
        Expanded(
          child: intro && !AppMotion.reduced(context)
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: value),
                  duration: const Duration(milliseconds: 620),
                  curve: AppMotion.pop,
                  builder: (_, v, _) => track(v),
                )
              : track(value),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 30,
          child: Text(
            '${label ?? value.round()}/$total',
            textAlign: TextAlign.right,
            style: t.labelMedium?.copyWith(
              color: AppColors.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    // Overshoot reads as stretch: let the fill run a little past its
    // slot, but never outside the track.
    final f = math.max(0.0, math.min(1.0, fraction));
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(99),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: f,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              colors: [AppColors.brandFill, AppColors.brand],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gives its child a quick "ready!" bump when [active] turns on – the CTA
/// waking up once the step is complete.
class CtaPulse extends StatefulWidget {
  const CtaPulse({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<CtaPulse> createState() => _CtaPulseState();
}

class _CtaPulseState extends State<CtaPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(CtaPulse old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active && !AppMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.scale(
      scale: 1 + 0.035 * math.sin(math.pi * _c.value),
      child: child,
    ),
    child: widget.child,
  );
}

/// Label above a form field, with an "Optional" tag.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});
  final String text;
  final bool optional;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Flexible(child: Text(text, style: t.titleSmall)),
          if (optional)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                context.s.optional,
                style: t.bodySmall?.copyWith(
                  fontSize: 12,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A form field that fades and lifts in as part of a step's cascade.
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    super.key,
    required this.index,
    required this.label,
    required this.child,
    this.optional = false,
  });

  /// Position in the step's cascade (title is 0, subtitle 1).
  final int index;
  final String label;
  final bool optional;
  final Widget child;

  @override
  Widget build(BuildContext context) => Reveal(
    index: index,
    offset: 12,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label, optional: optional),
          child,
        ],
      ),
    ),
  );
}

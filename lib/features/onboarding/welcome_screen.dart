import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../l10n/l10n.dart';

// Flow: Welcome → Business type → Employee skills → Business name → Offer →
//       Teach → Meet your AI employee → Test → Home

// ============================================================ 1. Welcome
/// The mascot pops in and floats, the copy rises in, and a "how it works"
/// strip plays the core loop on repeat (tap a step to jump to it).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppSpace.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        BrandWordmark(size: 19),
                        Spacer(),
                        LanguageChip(),
                      ],
                    ),
                    SizedBox(height: c.maxHeight * 0.03),
                    Center(
                      child: PopIn(
                        duration: const Duration(milliseconds: 720),
                        child: FloatIdle(
                          child: Mascot(
                            state: MascotState.welcome,
                            size: (c.maxHeight * 0.32).clamp(180, 280),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: c.maxHeight * 0.03),
                    Reveal(
                      index: 3,
                      child: Semantics(
                        header: true,
                        child: Text(
                          s.obWelcomeTitle,
                          textAlign: TextAlign.center,
                          style: t.displaySmall?.copyWith(
                            fontSize: 30,
                            height: 1.15,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Reveal(
                      index: 4,
                      child: Text(
                        s.obWelcomeSub,
                        textAlign: TextAlign.center,
                        style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    const Reveal(index: 6, child: _HowItWorks()),
                    const SizedBox(height: AppSpace.xl),
                    Reveal(
                      index: 8,
                      child: PrimaryButton(
                        label: s.createMyAiEmployee,
                        trailingArrow: true,
                        onPressed: () =>
                            context.push('/onboarding/business-type'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _loopIcons = [
  Icons.call_rounded,
  Icons.hearing_rounded,
  Icons.local_fire_department_rounded,
  Icons.chat_bubble_rounded,
  Icons.handshake_rounded,
];

/// Calls → listens → scores → drafts → you close, lighting up one step at
/// a time with a sentence for each. Under reduced motion it holds still
/// and the steps can be tapped through.
class _HowItWorks extends StatefulWidget {
  const _HowItWorks();
  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks>
    with SingleTickerProviderStateMixin {
  static const _n = 5;
  static const _perStep = Duration(milliseconds: 2100);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _perStep * _n,
  )..addListener(_onTick);
  int _active = 0;

  void _onTick() {
    final a = math.min(_n - 1, (_c.value * _n).floor());
    if (a != _active) setState(() => _active = a);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  void _jump(int i) {
    Haptics.tap();
    setState(() => _active = i);
    // Hold the chosen step a beat longer, then carry on round the loop.
    _c.value = (i + 0.02) / _n;
    if (!AppMotion.reduced(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final loop = s.obLoop;
    return Semantics(
      label: '${s.obHowItWorks}: ${loop.map((e) => e.$2).join('. ')}',
      child: ExcludeSemantics(
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
          child: Column(
            children: [
              Text(
                s.obHowItWorks,
                style: t.labelMedium?.copyWith(color: AppColors.inkFaint),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _n; i++) ...[
                    Expanded(
                      child: _LoopNode(
                        icon: _loopIcons[i],
                        label: loop[i].$1,
                        state: i == _active
                            ? _NodeState.active
                            : i < _active
                            ? _NodeState.passed
                            : _NodeState.ahead,
                        onTap: () => _jump(i),
                      ),
                    ),
                    if (i < _n - 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 19),
                        child: _Connector(lit: i < _active),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              // Reserve the tallest caption so the card never jumps.
              Stack(
                alignment: Alignment.center,
                children: [
                  for (final (_, caption) in loop)
                    Opacity(
                      opacity: 0,
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: t.titleSmall,
                      ),
                    ),
                  SwapFade(
                    child: Text(
                      loop[_active].$2,
                      key: ValueKey(_active),
                      textAlign: TextAlign.center,
                      style: t.titleSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NodeState { ahead, active, passed }

class _LoopNode extends StatelessWidget {
  const _LoopNode({
    required this.icon,
    required this.label,
    required this.state,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final _NodeState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = state == _NodeState.active;
    final (bg, fg) = switch (state) {
      _NodeState.active => (AppColors.brandFill, Colors.white),
      _NodeState.passed => (AppColors.brandSoft, AppColors.brand),
      _NodeState.ahead => (AppColors.surfaceMuted, AppColors.inkFaint),
    };
    const d = Duration(milliseconds: 320);
    return Pressable(
      scale: 0.9,
      haptic: false,
      onTap: onTap,
      child: Column(
        children: [
          AnimatedScale(
            scale: active ? 1.14 : 1,
            duration: d,
            curve: AppMotion.pop,
            child: AnimatedContainer(
              duration: d,
              curve: AppMotion.standard,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: active ? AppShadows.glow(AppColors.brand) : null,
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fg),
                duration: d,
                builder: (_, c, _) => Icon(icon, size: 19, color: c),
              ),
            ),
          ),
          const SizedBox(height: 7),
          AnimatedDefaultTextStyle(
            duration: d,
            style: (t.bodySmall ?? const TextStyle()).copyWith(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? AppColors.ink : AppColors.inkFaint,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The short line between two steps; fills with brand once passed.
class _Connector extends StatelessWidget {
  const _Connector({required this.lit});
  final bool lit;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 320),
    width: 8,
    height: 2,
    decoration: BoxDecoration(
      color: lit ? AppColors.brand : AppColors.border,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

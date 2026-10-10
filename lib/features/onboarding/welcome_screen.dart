import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';

// Flow: Welcome → Business type → Employee skills → Business name → Offer →
//       Teach → Meet your AI employee → Test → Home

// ============================================================ 1. Welcome
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.lg,
                  AppSpace.page,
                  AppSpace.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandWordmark(size: 19),
                    ),
                    SizedBox(height: c.maxHeight * 0.05),
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutBack,
                        builder: (_, v, child) => Transform.scale(
                          scale: 0.85 + 0.15 * v,
                          child: Opacity(opacity: v.clamp(0, 1), child: child),
                        ),
                        child: Mascot(
                          state: MascotState.welcome,
                          size: (c.maxHeight * 0.36).clamp(200, 300),
                        ),
                      ),
                    ),
                    SizedBox(height: c.maxHeight * 0.04),
                    Reveal(
                      index: 1,
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Your AI employee that calls every lead.',
                          textAlign: TextAlign.center,
                          style: t.displaySmall?.copyWith(
                            fontSize: 32,
                            height: 1.12,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    const _LoopStrip(),
                    const SizedBox(height: AppSpace.xxl + 4),
                    PrimaryButton(
                      label: 'Create My AI Employee',
                      trailingArrow: true,
                      onPressed: () =>
                          context.push('/onboarding/business-type'),
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

/// Visual reinforcement of the core loop.
class _LoopStrip extends StatelessWidget {
  const _LoopStrip();
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.call_outlined, 'Calls'),
      (Icons.psychology_outlined, 'Analyses'),
      (Icons.local_fire_department_outlined, 'Scores'),
      (Icons.chat_bubble_outline_rounded, 'Drafts'),
      (Icons.handshake_outlined, 'You close'),
    ];
    return Semantics(
      label: 'Calls, analyses, scores, drafts a follow-up, you close',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Reveal(
                      index: 4 + i,
                      offset: 8,
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.card,
                        ),
                        child: Icon(
                          steps[i].$1,
                          size: 19,
                          color: i == steps.length - 1
                              ? AppColors.brand
                              : AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        steps[i].$2,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkFaint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

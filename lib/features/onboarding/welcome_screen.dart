import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/brand.dart';
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
                padding: const EdgeInsets.all(AppSpace.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const BrandWordmark(size: 19),
                    const SizedBox(height: 22),
                    Text('Welcome to ${Brand.appName}', style: t.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${Brand.tagline}.',
                      style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                    ),
                    SizedBox(height: c.maxHeight * 0.02),
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
                          size: (c.maxHeight * 0.3).clamp(180, 260),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'HIRE YOUR AI EMPLOYEE',
                      style: t.labelSmall?.copyWith(
                        color: AppColors.brand,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Call leads, qualify customers, and follow up for your business.',
                      style: t.headlineSmall?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: 20),
                    const _LoopStrip(),
                    const SizedBox(height: 26),
                    PrimaryButton(
                      label: 'Create My AI Employee',
                      trailingArrow: true,
                      onPressed: () =>
                          context.push('/onboarding/business-type'),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        Brand.description,
                        style: t.bodySmall,
                        textAlign: TextAlign.center,
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

/// Visual reinforcement of the core loop.
class _LoopStrip extends StatelessWidget {
  const _LoopStrip();
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.call_rounded, 'Calls', AppColors.brand),
      (Icons.psychology_rounded, 'Analyses', AppColors.info),
      (Icons.local_fire_department_rounded, 'Scores', AppColors.hot),
      (Icons.chat_rounded, 'Drafts', AppColors.whatsapp),
      (Icons.handshake_rounded, 'You close', AppColors.warmInk),
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
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.card,
                        ),
                        child: Icon(steps[i].$1, size: 21, color: steps[i].$3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        steps[i].$2,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
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

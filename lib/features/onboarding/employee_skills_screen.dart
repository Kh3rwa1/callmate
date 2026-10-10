import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import 'onboarding_choice_card.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ================================================ 2b. What should it do?
class EmployeeSkillsScreen extends ConsumerWidget {
  const EmployeeSkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final suggested = d.suggestedAgent;
    final ready = d.skills.isNotEmpty;
    return OnboardingScaffold(
      step: 2,
      title: s.obSkillsTitle,
      subtitle: s.obSkillsSub,
      revealChildren: false,
      cta: CtaPulse(
        active: ready,
        child: PrimaryButton(
          label: s.continueLabel,
          onPressed: ready ? () => context.push('/onboarding/details') : null,
        ),
      ),
      children: [
        ChoiceGrid(
          children: [
            for (final skill in EmployeeSkill.values)
              OnboardingChoiceCard(
                icon: AppIcons.skill(skill),
                title: s.skill(skill),
                multi: true,
                selected: d.skills.contains(skill),
                onTap: () =>
                    ref.read(onboardingProvider.notifier).toggleSkill(skill),
              ),
          ],
        ),
        const SizedBox(height: 18),
        // Who they're getting updates live as skills change: the badge pops
        // and the sentence crossfades.
        Reveal(
          index: 6,
          child: AnimatedContainer(
            duration: AppMotion.base,
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.cardSm),
            ),
            child: Row(
              children: [
                PopSwitcher(
                  child: RoleBadge(
                    key: ValueKey(suggested.roleKind),
                    role: suggested.roleKind,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwapFade(
                    child: SizedBox(
                      key: ValueKey('${s.lang}-${suggested.role}'),
                      width: double.infinity,
                      child: Text(
                        s.obWeWillSetUp(s.data(suggested.role)),
                        style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

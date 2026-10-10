import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/templates/templates.dart';
import 'onboarding_controller.dart';
import 'onboarding_choice_card.dart';
import 'onboarding_scaffold.dart';

// ================================================ 2b. What should it do?
class EmployeeSkillsScreen extends ConsumerWidget {
  const EmployeeSkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final suggested = d.suggestedAgent;
    return OnboardingScaffold(
      step: 2,
      title: 'What should it do?',
      cta: PrimaryButton(
        label: 'Continue',
        onPressed: d.skills.isEmpty
            ? null
            : () => context.push('/onboarding/details'),
      ),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.75,
          children: [
            for (final s in EmployeeSkill.values)
              OnboardingChoiceCard(
                emoji: s.emoji,
                title: s.label,
                multi: true,
                selected: d.skills.contains(s),
                onTap: () =>
                    ref.read(onboardingProvider.notifier).toggleSkill(s),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(suggested.role),
            children: [
              RoleBadge(role: suggested.roleKind, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'We\'ll set up ${'AEIOU'.contains(suggested.role[0]) ? 'an' : 'a'} '
                  '${suggested.role} for you.',
                  style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

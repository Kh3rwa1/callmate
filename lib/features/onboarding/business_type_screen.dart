import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_card.dart';
import '../../data/templates/templates.dart';
import 'onboarding_controller.dart';
import 'onboarding_choice_card.dart';
import 'onboarding_scaffold.dart';

// ======================================================== 2. Business type
class BusinessTypeScreen extends ConsumerWidget {
  const BusinessTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    return OnboardingScaffold(
      step: 1,
      title: 'What type of business do you run?',
      subtitle:
          'We\'ll set up your AI employee with the right defaults. You can change anything later.',
      cta: PrimaryButton(
        label: 'Continue',
        onPressed: draft.category == null
            ? null
            : () => context.push('/onboarding/skills'),
      ),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            for (final tpl in businessTemplates)
              OnboardingChoiceCard(
                emoji: tpl.category.emoji,
                title: tpl.category.label,
                subtitle: tpl.agent.role,
                selected: draft.category == tpl.category,
                onTap: () => ref
                    .read(onboardingProvider.notifier)
                    .selectCategory(tpl.category),
              ),
          ],
        ),
      ],
    );
  }
}

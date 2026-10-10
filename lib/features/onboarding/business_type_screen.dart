import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import 'onboarding_choice_card.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ======================================================== 2. Business type
class BusinessTypeScreen extends ConsumerWidget {
  const BusinessTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final draft = ref.watch(onboardingProvider);
    final ready = draft.category != null;
    return OnboardingScaffold(
      step: 1,
      title: s.obTypeTitle,
      subtitle: s.obTypeSub,
      revealChildren: false,
      cta: CtaPulse(
        active: ready,
        child: PrimaryButton(
          label: s.continueLabel,
          onPressed: ready ? () => context.push('/onboarding/skills') : null,
        ),
      ),
      children: [
        if (draft.category case final c?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              key: const ValueKey('playbook-ready'),
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.obPlaybookReady(s.playbookName(playbookVerticalFor(c))),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ChoiceGrid(
          children: [
            for (final tpl in businessTemplates)
              OnboardingChoiceCard(
                icon: AppIcons.category(tpl.category),
                title: s.category(tpl.category),
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

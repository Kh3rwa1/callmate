import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import 'onboarding_choice_card.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ================================================ 1/3. Type of business
/// The first thing a new owner sees: what the app does in one line, and
/// big tiles for the type of business. One tap picks it and moves on.
class BusinessTypeScreen extends ConsumerStatefulWidget {
  const BusinessTypeScreen({super.key});

  @override
  ConsumerState<BusinessTypeScreen> createState() => _BusinessTypeScreenState();
}

class _BusinessTypeScreenState extends ConsumerState<BusinessTypeScreen> {
  bool _moving = false;

  Future<void> _pick(BusinessCategory c) async {
    ref.read(onboardingProvider.notifier).selectCategory(c);
    if (_moving) return;
    _moving = true;
    // A beat to see the tick, then on to the next step.
    await Future<void>.delayed(AppMotion.of(context, AppMotion.base));
    if (mounted) await context.push('/onboarding/name');
    _moving = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final draft = ref.watch(onboardingProvider);
    final ready = draft.category != null;
    return OnboardingScaffold(
      step: 1,
      title: s.obTypeQuestion,
      revealChildren: false,
      trailing: const LanguageChip(),
      cta: CtaPulse(
        active: ready,
        child: PrimaryButton(
          label: s.continueLabel,
          onPressed: ready ? () => context.push('/onboarding/name') : null,
        ),
      ),
      children: [
        Row(
          children: [
            const Mascot(state: MascotState.welcome, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.obTypeHint,
                style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (draft.category case final c?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              key: const ValueKey('playbook-ready'),
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.obPlaybookReady(s.playbookName(playbookVerticalFor(c))),
                    style: t.bodyLarge,
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
                onTap: () => _pick(tpl.category),
              ),
          ],
        ),
      ],
    );
  }
}

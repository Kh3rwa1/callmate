import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../l10n/l10n.dart';
import 'onboarding_scaffold.dart';

// ===================================================== 7. First AI call
/// A practice call with a sample customer. The "caller" rings (pulsing
/// rings round the avatar), their question types itself out, and the
/// employee waits on the line below.
class FirstCallScreen extends ConsumerWidget {
  const FirstCallScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(localPrefsProvider).setOnboarded(true);
    await ref.read(notificationServiceProvider).requestPermission();
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    final wf = ref.watch(workflowProvider);
    final tested = ref.watch(localPrefsProvider).agentTested;
    Future<void> talk() async {
      // Read before navigating: `ref` is unusable once this screen is
      // disposed (e.g. the voice test finishes onboarding with go()).
      final prefs = ref.read(localPrefsProvider);
      await context.push('/voice-test?from=onboarding');
      await prefs.setAgentTested(true);
    }

    return OnboardingScaffold(
      step: 6,
      title: s.obFirstCallTitle,
      subtitle: s.obFirstCallSub(name),
      revealChildren: false,
      cta: tested
          ? PrimaryButton(
              label: s.obGoToDashboard,
              trailingArrow: true,
              onPressed: () => _finish(context, ref),
            )
          : PrimaryButton(
              label: s.talkTo(name),
              icon: Icons.mic_rounded,
              onPressed: talk,
            ),
      secondary: tested
          ? TextButton(onPressed: talk, child: Text(s.obTalkAgainTo(name)))
          : TextButton(
              onPressed: () => _finish(context, ref),
              style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
              child: Text(s.skip),
            ),
      children: [
        Reveal(
          index: 2,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PulseRings(
                      size: 72,
                      color: AppColors.success,
                      child: LeadAvatar(name: wf.sampleLeadName, size: 48),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wf.sampleLeadName,
                            style: t.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            s.data(wf.sampleLeadInterest),
                            style: t.bodyMedium?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Pill(label: s.sample),
                  ],
                ),
                const SizedBox(height: 14),
                // Their question, as a chat bubble that types itself out.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: WordReveal(
                    s.data(wf.sampleLeadQuote),
                    perWord: const Duration(milliseconds: 55),
                    maxDuration: const Duration(milliseconds: 1300),
                    style: t.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: AppColors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s.obYouPlay,
                        style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Reveal(
          index: 4,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: AgentAvatar(size: 96, activity: EmployeeActivity.calling),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Reveal(
          index: 5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 15, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.obFreePractice,
                  style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

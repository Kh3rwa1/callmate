import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import 'onboarding_scaffold.dart';

// ===================================================== 7. First AI call
class FirstCallScreen extends ConsumerWidget {
  const FirstCallScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(localPrefsProvider).setOnboarded(true);
    await ref.read(notificationServiceProvider).requestPermission();
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    final wf = ref.watch(workflowProvider);
    final initials = wf.sampleLeadName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join();
    return OnboardingScaffold(
      step: 6,
      title: 'Make your first AI call',
      subtitle: '${wf.testCallerHint} Hear how $name handles it.',
      cta: PrimaryButton(
        label: 'Talk to $name',
        icon: Icons.mic_rounded,
        onPressed: () async {
          // Read before navigating: `ref` is unusable once this screen is
          // disposed (e.g. the voice test finishes onboarding with go()).
          final prefs = ref.read(localPrefsProvider);
          await context.push('/voice-test?from=onboarding');
          await prefs.setAgentTested(true);
        },
      ),
      secondary: TextButton(
        onPressed: () => _finish(context, ref),
        child: const Text('Go to my dashboard'),
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SAMPLE LEAD', style: t.labelSmall),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.hotSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initials,
                      style: t.titleMedium?.copyWith(color: AppColors.hot),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wf.sampleLeadName, style: t.titleLarge),
                        Text(wf.sampleLeadInterest, style: t.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  wf.sampleLeadQuote,
                  style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const EmployeeMascot(
              state: MascotState.calling,
              size: 96,
              halo: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$name introduces itself as an AI assistant, answers questions, and offers a ${wf.humanLabel.toLowerCase()} follow-up.',
                style: t.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          color: AppColors.successSoft,
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Test calls are free and never contact real leads.',
                  style: t.bodyMedium?.copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
        if (ref.watch(localPrefsProvider).agentTested) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Looks great – go to dashboard',
            color: AppColors.success,
            onPressed: () => _finish(context, ref),
          ),
        ],
      ],
    );
  }
}

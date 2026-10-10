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
      title: 'Your first call',
      cta: tested
          ? PrimaryButton(
              label: 'Go to dashboard',
              onPressed: () => _finish(context, ref),
            )
          : PrimaryButton(
              label: 'Talk to $name',
              icon: Icons.mic_rounded,
              onPressed: talk,
            ),
      secondary: tested
          ? TextButton(onPressed: talk, child: Text('Talk to $name again'))
          : TextButton(
              onPressed: () => _finish(context, ref),
              style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
              child: const Text('Skip'),
            ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Text(initials, style: t.titleMedium),
                  ),
                  const SizedBox(width: 14),
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
                          wf.sampleLeadInterest,
                          style: t.bodyMedium?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Pill(label: 'Sample'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                wf.sampleLeadQuote,
                style: t.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Center(
          child: EmployeeMascot(
            state: MascotState.calling,
            size: 120,
            halo: false,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 15,
              color: AppColors.inkFaint,
            ),
            const SizedBox(width: 6),
            Text(
              'Free · never calls real leads',
              style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
            ),
          ],
        ),
      ],
    );
  }
}

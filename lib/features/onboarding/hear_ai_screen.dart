import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../agent/owner_test_call_sheet.dart';
import 'onboarding_scaffold.dart';

// ===================================================== 3/3. Hear your AI
/// "Call me now": the employee rings the owner's own phone. Outside calling
/// hours the panel offers the in-app voice test instead. Skip goes home.
class HearAiScreen extends ConsumerWidget {
  const HearAiScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(localPrefsProvider);
    final notif = ref.read(notificationServiceProvider);
    await prefs.setOnboarded(true);
    await notif.requestPermission();
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final name = ref.watch(employeeNameProvider);
    return OnboardingScaffold(
      mascot: MascotState.calling,
      step: 3,
      title: s.obHearTitle,
      subtitle: s.obHearSub(name),
      revealChildren: false,
      cta: TextButton(
        key: const Key('hear-skip'),
        onPressed: () => _finish(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkSoft,
          minimumSize: const Size.fromHeight(48),
        ),
        child: Text(s.skip),
      ),
      children: [
        const Center(
          child: AgentAvatar(size: 110, activity: EmployeeActivity.calling),
        ),
        const SizedBox(height: 24),
        OwnerTestCallPanel(
          showTitle: false,
          doneLabel: s.goToHome,
          onDone: () => _finish(context, ref),
          onTalkInApp: () => context.push('/voice-test?from=onboarding'),
        ),
      ],
    );
  }
}

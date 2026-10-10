import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import 'onboarding_controller.dart';

enum _Phase { learning, ready, meet }

// =========================================== 6. Meet your AI employee
/// While the business saves, the employee visibly "learns": a checklist
/// ticks off step by step with rings pulsing around the thinking mascot.
/// Then a beat of "All set!", and the reveal: the mascot bounces in with
/// confetti, ready to be named.
class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  static const _steps = 3; // = S.obLearning.length
  static const _stepTime = Duration(milliseconds: 700);

  _Phase _phase = _Phase.learning;
  int _done = 0; // learning steps finished
  int _generation = 0; // a retry makes earlier runs stale
  bool _activating = false;
  bool _nameMissing = false;
  int _shakes = 0;
  Object? _error;
  late final TextEditingController _name;
  late final TextEditingController _role;

  @override
  void initState() {
    super.initState();
    final d = ref.read(onboardingProvider);
    final a = d.suggestedAgent;
    _name = TextEditingController(text: d.employeeName ?? a.defaultName);
    _role = TextEditingController(text: d.employeeRole ?? a.role);
    _learn();
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _phase = _Phase.learning;
      _done = 0;
    });
    _learn();
  }

  Future<void> _learn() async {
    final run = ++_generation;
    bool live() => mounted && run == _generation;
    try {
      final f = ref.read(onboardingProvider.notifier).saveBusiness();
      // Awaited after the animation; mark it handled now so an early failure
      // isn't reported as an unhandled async error (it still throws below).
      f.ignore();
      for (var i = 1; i <= _steps; i++) {
        await Future<void>.delayed(_stepTime);
        if (!live()) return;
        setState(() => _done = i);
      }
      await f;
      if (!live()) return;
      setState(() => _phase = _Phase.ready);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!live()) return;
      Haptics.warn();
      setState(() => _phase = _Phase.meet);
    } catch (e) {
      if (live()) setState(() => _error = e);
    }
  }

  Future<void> _activate() async {
    final s = context.s;
    if (_name.text.trim().isEmpty) {
      Haptics.warn();
      setState(() {
        _nameMissing = true;
        _shakes++;
      });
      return;
    }
    setState(() => _activating = true);
    ref
        .read(onboardingProvider.notifier)
        .update(
          (d) => d.copyWith(
            employeeName: _name.text.trim(),
            employeeRole: _role.text.trim(),
          ),
        );
    try {
      await ref.read(onboardingProvider.notifier).activateEmployee();
      // The business and agent now exist server-side; a relaunch from the
      // optional first-call step should land on home, not redo onboarding.
      await ref.read(localPrefsProvider).setOnboarded(true);
      if (mounted) context.push('/onboarding/test');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final Widget body;
    if (error != null) {
      body = _ErrorView(
        key: const ValueKey('error'),
        error: error,
        onRetry: _retry,
      );
    } else if (_phase == _Phase.meet) {
      body = _meet(context);
    } else {
      body = _LearningView(
        key: const ValueKey('learning'),
        done: _done,
        steps: _steps,
        ready: _phase == _Phase.ready,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, const Duration(milliseconds: 520)),
          switchInCurve: AppMotion.emphasized,
          switchOutCurve: AppMotion.exit,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(a),
              child: child,
            ),
          ),
          child: body,
        ),
      ),
    );
  }

  Widget _meet(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final at = ref.watch(onboardingProvider).suggestedAgent;
    final roleKind = EmployeeRoleKind.fromRole(_role.text);
    return Column(
      key: const ValueKey('meet'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpace.page),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Reveal(
                  child: Semantics(
                    header: true,
                    child: Text(
                      s.obMeet,
                      style: t.titleMedium?.copyWith(color: AppColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // The reveal: bounce in, confetti over the top.
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: AppMotion.of(
                        context,
                        const Duration(milliseconds: 900),
                      ),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) =>
                          Transform.scale(scale: 0.55 + 0.45 * v, child: child),
                      child: Mascot(
                        state: MascotState.success,
                        size: 180,
                        role: roleKind,
                      ),
                    ),
                    const Positioned.fill(
                      child: OverflowBox(
                        maxWidth: 340,
                        maxHeight: 340,
                        child: ConfettiBurst(size: 340, count: 36),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Reveal(
                  index: 3,
                  child: ValueListenableBuilder(
                    valueListenable: _name,
                    builder: (_, v, _) => Text(
                      v.text.trim().isEmpty ? s.obNameYourEmployee : v.text,
                      style: t.displaySmall,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Reveal(
                  index: 4,
                  child: ValueListenableBuilder(
                    valueListenable: _role,
                    builder: (_, v, _) => Text(
                      s.data(v.text),
                      style: t.titleMedium?.copyWith(color: AppColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Reveal(
                  index: 5,
                  child: Pill(
                    icon: Icon(
                      Icons.translate_rounded,
                      size: 14,
                      color: AppColors.inkSoft,
                    ),
                    label: '${s.obSpeaks}: ${s.dataList(at.languages)}',
                  ),
                ),
                const SizedBox(height: 28),
                Reveal(
                  index: 6,
                  child: Shake(
                    trigger: _shakes,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Column(
                        children: [
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: s.nameLabel,
                              errorText: _nameMissing ? s.nameRequired : null,
                            ),
                            onChanged: (_) {
                              if (_nameMissing) {
                                setState(() => _nameMissing = false);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _role,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(labelText: s.roleLabel),
                            // The badge follows the role as it's typed.
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Reveal(
          index: 7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              8,
              AppSpace.page,
              16,
            ),
            child: PrimaryButton(
              label: s.obActivate,
              icon: Icons.bolt_rounded,
              loading: _activating,
              onPressed: _activate,
            ),
          ),
        ),
      ],
    );
  }
}

/// Thinking mascot inside pulsing rings, a progress bar, and the checklist
/// of what it is learning.
class _LearningView extends StatelessWidget {
  const _LearningView({
    super.key,
    required this.done,
    required this.steps,
    required this.ready,
  });
  final int done;
  final int steps;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final lines = s.obLearning;
    final progress = ready ? 1.0 : 0.08 + 0.84 * (done / steps);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              child: PulseRings(
                size: 260,
                color: AppColors.brand,
                child: Mascot(
                  state: ready ? MascotState.success : MascotState.thinking,
                  size: 190,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              label: ready ? s.obAllSet : s.obAlmostReady,
              child: SizedBox(
                width: 220,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: AppMotion.of(
                    context,
                    const Duration(milliseconds: 600),
                  ),
                  curve: AppMotion.emphasized,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    borderRadius: const BorderRadius.all(Radius.circular(9)),
                    backgroundColor: AppColors.border,
                    color: ready ? AppColors.success : AppColors.brand,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++)
                    Reveal(
                      index: 2 + i,
                      offset: 8,
                      child: _LearnRow(
                        text: lines[i],
                        state: i < done
                            ? _Step.done
                            : i == done
                            ? _Step.active
                            : _Step.pending,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 34,
              child: SwapFade(
                child: ready
                    ? PopIn(
                        key: const ValueKey('ready'),
                        child: Text(
                          s.obAllSet,
                          style: t.titleLarge?.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('working')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step { pending, active, done }

class _LearnRow extends StatelessWidget {
  const _LearnRow({required this.text, required this.state});
  final String text;
  final _Step state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final Widget lead = switch (state) {
      _Step.done => SuccessCheck(
        key: const ValueKey('done'),
        size: 22,
        color: AppColors.success,
      ),
      _Step.active => SizedBox.square(
        key: const ValueKey('active'),
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: AppColors.brand,
        ),
      ),
      _Step.pending => Container(
        key: const ValueKey('pending'),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: Center(child: PopSwitcher(child: lead)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: AppMotion.base,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: switch (state) {
                  _Step.pending => AppColors.inkFaint,
                  _Step.active => AppColors.ink,
                  _Step.done => AppColors.inkSoft,
                },
              ),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final e = error;
    final text = e.toString().toLowerCase();
    final isAuth =
        (e is ApiException && e.isAuth) ||
        text.contains('unauthorized') ||
        text.contains('missing token') ||
        text.contains('401');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PopIn(child: Mascot(state: MascotState.error, size: 170)),
            const SizedBox(height: 16),
            Reveal(
              index: 2,
              child: Text(
                isAuth ? s.obSignInRequired : s.obSetupFailed,
                style: t.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Reveal(
              index: 3,
              child: Text(
                isAuth ? s.obSignInToConnect : friendlyError(error, s),
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Reveal(
              index: 4,
              child: isAuth
                  ? Column(
                      children: [
                        PrimaryButton(
                          label: s.signIn,
                          onPressed: () => context.go('/login'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(onPressed: onRetry, child: Text(s.tryAgain)),
                      ],
                    )
                  : PrimaryButton(label: s.tryAgain, onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

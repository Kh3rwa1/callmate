import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/templates/templates.dart';
import 'onboarding_controller.dart';

// =========================================== 6. Meet your AI employee
class CreateAgentScreen extends ConsumerStatefulWidget {
  const CreateAgentScreen({super.key});
  @override
  ConsumerState<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends ConsumerState<CreateAgentScreen> {
  int _phase = 0; // 0 learning → 1 meet
  bool _activating = false;
  Object? _error;
  late final TextEditingController _name;
  late final TextEditingController _role;
  static const _learning = [
    'Reading your business details…',
    'Learning what you offer…',
    'Practising customer calls…',
  ];
  int _line = 0;

  @override
  void initState() {
    super.initState();
    final a = ref.read(onboardingProvider).suggestedAgent;
    _name = TextEditingController(
      text: ref.read(onboardingProvider).employeeName ?? a.defaultName,
    );
    _role = TextEditingController(
      text: ref.read(onboardingProvider).employeeRole ?? a.role,
    );
    _run();
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _phase = 0;
      _line = 0;
    });
    try {
      final f = ref.read(onboardingProvider.notifier).saveBusiness();
      // Awaited after the animation; mark it handled now so an early failure
      // isn't reported as an unhandled async error (it still throws below).
      f.ignore();
      for (var i = 1; i < _learning.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 850));
        if (!mounted) return;
        setState(() => _line = i);
      }
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _phase = 1);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _activate() async {
    if (_name.text.trim().isEmpty) return;
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
      if (mounted) context.push('/onboarding/test');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = ref.watch(onboardingProvider);
    final at = d.suggestedAgent;
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(state: MascotState.error, size: 170),
                  const SizedBox(height: 16),
                  Text(
                    'We couldn\'t set up your AI employee',
                    style: t.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text('Something went wrong. Try again.', style: t.bodyMedium),
                  const SizedBox(height: 24),
                  PrimaryButton(label: 'Try again', onPressed: _run),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final roleKind = EmployeeRoleKind.fromRole(_role.text);
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _phase == 0
              ? Center(
                  key: const ValueKey('learning'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Mascot(state: MascotState.thinking, size: 200),
                      const SizedBox(height: 28),
                      const SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _learning[_line],
                          key: ValueKey(_line),
                          style: t.titleMedium,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  key: const ValueKey('meet'),
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpace.page),
                        child: Column(
                          children: [
                            Text(
                              'Meet your AI employee 👋',
                              style: t.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.elasticOut,
                              builder: (_, v, child) => Transform.scale(
                                scale: 0.6 + 0.4 * v,
                                child: child,
                              ),
                              child: Mascot(
                                state: MascotState.success,
                                size: 190,
                                role: roleKind,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder(
                              valueListenable: _name,
                              builder: (_, v, _) => Text(
                                v.text.isEmpty ? 'Name your employee' : v.text,
                                style: t.displaySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            ValueListenableBuilder(
                              valueListenable: _role,
                              builder: (_, v, _) => Text(
                                v.text,
                                style: t.titleMedium?.copyWith(
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AppCard(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _name,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText: 'Name',
                                            prefixIcon: Icon(
                                              Icons.badge_outlined,
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _role,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      labelText: 'Role',
                                      prefixIcon: Icon(
                                        Icons.work_outline_rounded,
                                      ),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const Divider(height: 32),
                                  _Trait(
                                    label: 'Languages',
                                    value: at.languages.join(' · '),
                                  ),
                                  const SizedBox(height: 14),
                                  const _Trait(
                                    label: 'Personality',
                                    value: 'Friendly · Professional',
                                  ),
                                  const SizedBox(height: 14),
                                  _Trait(label: 'Goal', value: at.goal),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Your AI employee always introduces itself as an AI assistant.',
                              style: t.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.page,
                        8,
                        AppSpace.page,
                        16,
                      ),
                      child: PrimaryButton(
                        label: 'Activate Employee',
                        icon: Icons.bolt_rounded,
                        color: AppColors.success,
                        loading: _activating,
                        onPressed: _activate,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Trait extends StatelessWidget {
  const _Trait({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(label, style: t.bodyMedium)),
        Expanded(child: Text(value, style: t.titleSmall)),
      ],
    );
  }
}

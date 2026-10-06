import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Shared onboarding frame: progress, back, scrollable body, sticky CTA.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.children,
    required this.cta,
    this.total = 6,
    this.secondary,
  });

  final int step;
  final int total;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget cta;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.canPop() ? context.pop() : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      label: 'Step $step of $total',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: step / total),
                          duration: const Duration(milliseconds: 400),
                          builder: (_, v, __) =>
                              LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: AppColors.border, color: AppColors.brand),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('$step/$total', style: t.labelMedium),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 24, AppSpace.page, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(title, style: t.headlineMedium)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(subtitle!, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                    ],
                    const SizedBox(height: 28),
                    ...children,
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 16),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cta,
                  if (secondary != null) ...[const SizedBox(height: 4), secondary!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});
  final String text;
  final bool optional;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleSmall),
        if (optional) Text('  Optional', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

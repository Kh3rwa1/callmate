import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final u = ref.watch(usageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan & usage')),
      body: AsyncView<Usage>(
        value: u,
        onRetry: () => ref.invalidate(usageProvider),
        data: (u) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
          children: [
            AppCard(
              color: AppColors.ink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.subscription.planName.toUpperCase(), style: t.labelSmall?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Text(
                    '${Fmt.number(u.subscription.includedMinutes)} calling minutes',
                    style: t.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: u.ratio),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(9),
                      backgroundColor: Colors.white24,
                      color: u.ratio > 0.85 ? AppColors.hot : AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _Big(Fmt.number(u.minutesUsed), 'used')),
                      Expanded(child: _Big(Fmt.number(u.minutesRemaining), 'remaining')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                children: [
                  _Kv('Calls made', Fmt.number(u.callsMade)),
                  _Kv('Minutes used', '${Fmt.number(u.minutesUsed)} min'),
                  _Kv('Remaining', '${Fmt.number(u.minutesRemaining)} min'),
                  _Kv('Renews on', DateFormat('d MMM yyyy').format(u.subscription.renewsAt)),
                  _Kv('Extra minutes', '${Fmt.inr(u.ratePerMinuteInr)} / min', last: true),
                ],
              ),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Upgrade',
              icon: Icons.workspace_premium_rounded,
              color: AppColors.brand,
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Our team will reach out on WhatsApp to upgrade your plan.'))),
            ),
            const SizedBox(height: 10),
            Text('Only connected call minutes are counted.', style: t.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.v, this.l);
  final String v;
  final String l;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(v, style: t.headlineMedium?.copyWith(color: Colors.white)),
        Text(l, style: t.bodySmall?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.last = false});
  final String k;
  final String v;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(k, style: t.bodyMedium)),
          Text(v, style: t.titleSmall),
        ],
      ),
    );
  }
}

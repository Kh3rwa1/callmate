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
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            0,
            AppSpace.page,
            32,
          ),
          children: [
            AppCard(
              color: AppColors.ink,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.subscription.planName,
                    style: t.labelMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.number(u.minutesRemaining),
                      style: t.displaySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 52,
                        height: 1,
                        letterSpacing: -1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'minutes remaining',
                    style: t.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 22),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: u.ratio),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: Colors.white24,
                      color: u.ratio > 0.85 ? AppColors.hot : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${Fmt.number(u.minutesUsed)} used',
                          style: t.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ),
                      Text(
                        'of ${Fmt.number(u.subscription.includedMinutes)}',
                        style: t.bodySmall?.copyWith(color: Colors.white70),
                      ),
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
                  _Kv(
                    'Renews on',
                    DateFormat('d MMM yyyy').format(u.subscription.renewsAt),
                  ),
                  _Kv(
                    'Extra minutes',
                    '${Fmt.inr(u.ratePerMinuteInr)} / min',
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Upgrade',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Our team will reach out on WhatsApp to upgrade your plan.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only connected minutes count.',
              style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(k, style: t.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              v,
              style: t.titleSmall,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

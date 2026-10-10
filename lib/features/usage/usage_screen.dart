import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final usage = ref.watch(usageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.planAndUsage)),
      body: AsyncView<Usage>(
        value: usage,
        onRetry: () => ref.invalidate(usageProvider),
        data: (u) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            0,
            AppSpace.page,
            32,
          ),
          children: [
            Reveal(
              child: AppCard(
                color: AppColors.strong,
                border: Border.all(color: Colors.transparent),
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.data(u.subscription.planName),
                      style: t.labelLarge?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedCount(
                      value: u.minutesRemaining,
                      countUp: true,
                      format: Fmt.number,
                      style: t.displaySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 52,
                        height: 1,
                        letterSpacing: -1.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.minutesRemaining,
                      style: t.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 22),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: u.ratio),
                      duration: AppMotion.of(
                        context,
                        const Duration(milliseconds: 1100),
                      ),
                      curve: AppMotion.emphasized,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(6),
                        backgroundColor: Colors.white24,
                        color: u.ratio > 0.85
                            ? const Color(0xFFFF7A7F)
                            : AppColors.liveDot,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.nUsed(Fmt.number(u.minutesUsed)),
                            style: t.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ),
                        Text(
                          s.ofTotal(Fmt.number(u.subscription.includedMinutes)),
                          style: t.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Reveal(
              index: 1,
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _Kv(s.callsMade, Fmt.number(u.callsMade)),
                    _Kv(s.renewsOn, s.date(u.subscription.renewsAt)),
                    _Kv(
                      s.extraMinutes,
                      s.perMin(Fmt.inr(u.ratePerMinuteInr)),
                      last: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Reveal(
              index: 2,
              child: PrimaryButton(
                label: s.upgrade,
                icon: Icons.workspace_premium_outlined,
                color: AppColors.brandFill,
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(s.upgradeContact))),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              s.onlyConnectedCount,
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
            : Border(bottom: BorderSide(color: AppColors.border)),
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

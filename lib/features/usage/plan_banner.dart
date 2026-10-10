import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// The home-screen message for [u], or null when the plan needs no attention.
String? planBannerMessage(S s, Usage u) {
  if (u.subscription.status.blocksCalling) return s.bannerPastDue;
  if (u.subscription.isTrial) {
    if (u.exhausted) return s.bannerTrialUsedUp;
    if (u.trialLow) return s.bannerTrialLow(Fmt.number(u.minutesRemaining));
    return null;
  }
  if (u.exhausted && u.subscription.includedMinutes > 0) {
    return s.bannerMinutesUsedUp;
  }
  return null;
}

/// Payment due / trial running low banner. Taps through to Plan & usage.
class PlanBanner extends ConsumerWidget {
  const PlanBanner({super.key, this.padding = EdgeInsets.zero});

  /// Applied only while the banner is visible.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(usageProvider).value;
    final s = context.s;
    final message = u == null ? null : planBannerMessage(s, u);
    if (u == null || message == null) {
      return const SizedBox(width: double.infinity);
    }
    final urgent = u.subscription.status.blocksCalling || u.exhausted;
    final fg = urgent ? AppColors.hot : AppColors.warmInk;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: AppCard(
        key: const ValueKey('plan-banner'),
        color: urgent ? AppColors.hotSoft : AppColors.warmSoft,
        border: Border.all(color: Colors.transparent),
        shadow: false,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        onTap: () => context.push('/usage'),
        semanticLabel: message,
        child: Row(
          children: [
            Icon(
              urgent ? Icons.error_outline_rounded : Icons.hourglass_bottom,
              color: fg,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: t.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              u.subscription.isTrial ? s.upgrade : s.viewPlan,
              style: t.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: fg, size: 20),
          ],
        ),
      ),
    );
  }
}

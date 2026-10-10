import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// "Call New Leads" CTA. Full-width button on Home; [compact] is a small
/// pill for headers (Leads).
class CallNewLeadsButton extends StatelessWidget {
  const CallNewLeadsButton({
    super.key,
    required this.count,
    this.compact = false,
  });
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (compact) {
      return Semantics(
        button: true,
        label: s.callNewSemantics(count),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => context.push('/campaign/new'),
          scale: 0.94,
          child: Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
            decoration: BoxDecoration(
              color: AppColors.inverse,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone_forwarded_rounded,
                  size: 16,
                  color: AppColors.onInverse,
                ),
                const SizedBox(width: 6),
                Text(
                  s.callNewCompact(count),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.onInverse,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PrimaryButton(
      label: s.callNewLeadsCount(count),
      icon: Icons.phone_forwarded_rounded,
      onPressed: () => context.push('/campaign/new'),
    );
  }
}

/// Compact live banner shown on Home while a campaign is running. The bar
/// and counts glide as results come in.
class CampaignLiveBanner extends ConsumerWidget {
  const CampaignLiveBanner({super.key, required this.campaign});
  final Campaign campaign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final st = campaign.stats;
    return AppCard(
      color: AppColors.strong,
      border: Border.all(color: Colors.transparent),
      onTap: () => context.push('/campaigns/${campaign.id}'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          const AgentAvatar(
            size: 44,
            onDark: true,
            showRole: false,
            activity: EmployeeActivity.calling,
          ),
          const SizedBox(width: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.isCallingYourLeads(ref.watch(employeeNameProvider)),
                  style: t.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                SwapFade(
                  child: Text(
                    s.campaignBannerStats(st.completed, st.total, st.hot),
                    key: ValueKey('${st.completed}-${st.hot}'),
                    style: t.bodySmall?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: st.progress),
                  duration: AppMotion.of(context, AppMotion.slow),
                  curve: AppMotion.emphasized,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(9),
                    backgroundColor: Colors.white24,
                    color: AppColors.liveDot,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

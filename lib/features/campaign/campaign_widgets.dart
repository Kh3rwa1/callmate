import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

/// Primary "Call New Leads" CTA (Home + Leads).
class CallNewLeadsButton extends StatelessWidget {
  const CallNewLeadsButton({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: count > 0 ? 'Call $count New Leads' : 'Call New Leads',
      icon: Icons.phone_forwarded_rounded,
      color: AppColors.brand,
      onPressed: () => context.push('/campaign/new'),
    );
  }
}

/// Compact live banner shown on Home while a campaign is running.
class CampaignLiveBanner extends ConsumerWidget {
  const CampaignLiveBanner({super.key, required this.campaign});
  final Campaign campaign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final s = campaign.stats;
    return AppCard(
      color: AppColors.ink,
      onTap: () => context.push('/campaigns/${campaign.id}'),
      padding: const EdgeInsets.fromLTRB(10, 12, 18, 14),
      child: Row(
        children: [
          const MascotAvatar(size: 52, state: MascotState.calling),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ref.watch(employeeNameProvider)} is calling your leads…',
                  style: t.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.completed} of ${s.total} done · ${s.hot} hot',
                  style: t.bodySmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: s.progress),
                  duration: const Duration(milliseconds: 500),
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(9),
                    backgroundColor: Colors.white24,
                    color: AppColors.success,
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

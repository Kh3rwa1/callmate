import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

/// The plan the business is on.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AppRepository>().data.usage;

    if (usage == null) {
      return PageScaffold(
        title: 'Subscription',
        child: EmptyBlock(
          title: 'No plan yet',
          message: 'Your plan details will appear here once your account is set up.',
        ),
      );
    }

    return PageScaffold(
      title: 'Subscription',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatusPill(label: 'Active', tone: Tone.green),
                const SizedBox(height: AppSpacing.md),
                Text(usage.planName, style: AppText.hero),
                const SizedBox(height: 4),
                Text(
                  '₹${usage.pricePerMonth.toStringAsFixed(0)} per month',
                  style: AppText.body.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'What's included'),
          KeyValueTile(
            label: 'Minutes included',
            value: '${usage.minutesUsed + usage.creditsRemaining}',
            tone: Tone.green,
          ),
          const SizedBox(height: AppSpacing.sm),
          KeyValueTile(label: 'Calls this cycle', value: '${usage.callsMade}'),
          if (usage.renewsAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            KeyValueTile(
              label: 'Renews on',
              value: '${usage.renewsAt!.day}/${usage.renewsAt!.month}/${usage.renewsAt!.year}',
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          SecondaryButton(
            label: 'Talk to us about upgrading',
            icon: Icons.trending_up_rounded,
            onPressed: () => showAppToast(context, 'We will be in touch shortly'),
          ),
        ],
      ),
    );
  }
}

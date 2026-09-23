import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

/// How much of this cycle's allowance has been used.
class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AppRepository>().data.usage;

    if (usage == null) {
      return PageScaffold(
        title: 'Usage',
        child: EmptyBlock(
          title: 'No usage to show yet',
          message: 'Once your AI employee starts calling, your minutes and calls appear here.',
        ),
      );
    }

    final minutesIncluded = usage.minutesUsed + usage.creditsRemaining;

    return PageScaffold(
      title: 'Usage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Text(
                  '${usage.minutesUsed}',
                  style: AppText.display.copyWith(color: AppColors.brand),
                ),
                Text(
                  'minutes used this cycle',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: AppSpacing.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: minutesIncluded == 0 ? 0 : usage.minutesUsed / minutesIncluded,
                    minHeight: 8,
                    backgroundColor: AppColors.secondary,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${usage.creditsRemaining} minutes left',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'This cycle'),
          KeyValueTile(label: 'Calls made', value: '${usage.callsMade}'),
          const SizedBox(height: AppSpacing.sm),
          KeyValueTile(label: 'Minutes used', value: '${usage.minutesUsed}'),
          const SizedBox(height: AppSpacing.sm),
          KeyValueTile(label: 'Minutes left', value: '${usage.creditsRemaining}'),

          const SizedBox(height: AppSpacing.lg),
          Text(
            'Usage is reported by our backend from the calls it places on your behalf.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

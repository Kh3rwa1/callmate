import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';

/// Label/value row in the campaign setup summary. Long values wrap under
/// their own column instead of breaking mid-word on the right edge.
class CampaignSummaryRow extends StatelessWidget {
  const CampaignSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.leading,
  });
  final String label;
  final String value;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    value,
                    style: t.titleSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pre-flight checklist item on the campaign setup screen.
class CampaignChecklistItem extends StatelessWidget {
  const CampaignChecklistItem(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    onChanged: (v) {
      Haptics.tap();
      onChanged(v ?? false);
    },
    title: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
  );
}

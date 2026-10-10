import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LeadDetailRow extends StatelessWidget {
  const LeadDetailRow(
    this.k,
    this.v, {
    super.key,
    this.highlight = false,
    this.last = false,
  });
  final String k;
  final String v;
  final bool highlight;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              k,
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleSmall?.copyWith(
                color: highlight ? AppColors.brand : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LeadSignalChip extends StatelessWidget {
  const LeadSignalChip({super.key, required this.text, required this.positive});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          positive
              ? Icons.add_circle_outline_rounded
              : Icons.remove_circle_outline_rounded,
          size: 19,
          color: positive ? AppColors.success : AppColors.inkFaint,
          semanticLabel: positive ? 'Positive' : 'Concern',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

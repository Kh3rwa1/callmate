import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

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
            : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              k,
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              v,
              textAlign: TextAlign.right,
              maxLines: 2,
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
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive
                ? Icons.add_circle_outline_rounded
                : Icons.remove_circle_outline_rounded,
            size: 19,
            color: positive ? AppColors.success : AppColors.warmInk,
            semanticLabel: positive ? s.positive : s.concern,
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
}

/// The lead's consent evidence trail (newest first). Quiet on errors: it is
/// supporting information, not something the owner needs to act on.
class ConsentHistoryCard extends ConsumerWidget {
  const ConsentHistoryCard({super.key, required this.leadId});
  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final events =
        ref.watch(leadConsentHistoryProvider(leadId)).value ??
        const <ConsentEvent>[];
    if (events.isEmpty) {
      return AppCard(child: Text(s.consentHistoryEmpty, style: t.bodyMedium));
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == events.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.consentValue(events[i].consentValue),
                          style: t.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.consentSource(events[i].source),
                          style: t.bodySmall?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.date(events[i].createdAt),
                    style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

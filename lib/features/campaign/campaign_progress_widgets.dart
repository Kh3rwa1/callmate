import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Big number + label, one of a row of metrics on the progress screen. The
/// number glides to each new value and gives a small pop when it changes.
class CampaignStatTile extends StatelessWidget {
  const CampaignStatTile(this.label, this.value, this.color, {super.key});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$value $label',
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(value),
              tween: Tween(begin: 1.18, end: 1),
              duration: AppMotion.of(context, AppMotion.slow),
              curve: AppMotion.pop,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: AnimatedCount(
                value: value,
                duration: const Duration(milliseconds: 500),
                style: t.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: t.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Recent call row on the campaign progress screen.
class CampaignRecentCallTile extends ConsumerWidget {
  const CampaignRecentCallTile({super.key, required this.callId});
  final String callId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final call = ref.watch(callProvider(callId)).value;
    if (call == null) {
      return const SizedBox(
        height: 70,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Skeleton(height: 44),
          ),
        ),
      );
    }
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.push(
        call.status.isConnected
            ? '/calls/${call.id}/result'
            : '/calls/${call.id}',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            LeadAvatar(
              name: call.leadName,
              temperature:
                  call.leadScore?.temperature ?? LeadTemperature.unknown,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.leadName,
                    style: t.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (call.status.isConnected)
                    Text(
                      call.outcome ?? s.callStatus(call.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (call.leadScore != null)
              ScoreBadge(score: call.leadScore)
            else
              Pill(label: s.callStatus(call.status), dense: true),
          ],
        ),
      ),
    );
  }
}

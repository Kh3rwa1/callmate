import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

/// Single metric tile on the campaign progress screen.
class CampaignStatTile extends StatelessWidget {
  const CampaignStatTile(this.label, this.value, this.color, {super.key});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      semanticLabel: '$value $label',
      padding: const EdgeInsets.all(12),
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: t.headlineMedium?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
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
    final call = ref.watch(callProvider(callId)).value;
    if (call == null) {
      return const SizedBox(
        height: 70,
        child: Center(child: Skeleton(height: 50)),
      );
    }
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push(
          call.status.isConnected
              ? '/calls/${call.id}/result'
              : '/calls/${call.id}',
        ),
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
                  Text(call.leadName, style: t.titleSmall),
                  Text(
                    call.status.isConnected
                        ? call.outcome ?? 'Connected'
                        : call.status.label,
                    style: t.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (call.leadScore != null)
              ScoreBadge(score: call.leadScore)
            else
              const Pill(label: 'No answer'),
          ],
        ),
      ),
    );
  }
}

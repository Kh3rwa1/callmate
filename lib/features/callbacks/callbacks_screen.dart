import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

class CallbacksScreen extends ConsumerWidget {
  const CallbacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cbs = ref.watch(callbacksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Callbacks')),
      body: AsyncView<List<Callback>>(
        value: cbs,
        onRetry: () => ref.invalidate(callbacksProvider),
        data: (list) {
          final upcoming = list.where((c) => c.status == CallbackStatus.scheduled).toList();
          final done = list.where((c) => c.status != CallbackStatus.scheduled).toList();
          if (upcoming.isEmpty && done.isEmpty) {
            return const EmptyState(
              title: 'No callbacks yet',
              message: 'When a lead asks to talk to your counsellor, it shows up here.',
              mascot: MascotState.thinking,
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
            children: [
              Text('Leads who asked to speak with your counsellor.', style: t.bodyMedium),
              const SectionLabel('Upcoming'),
              if (upcoming.isEmpty) AppCard(child: Text('All caught up 🎉', style: t.titleSmall)),
              for (final c in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey(c.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await ref.read(callbackRepoProvider).markDone(c.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Marked ${c.leadName.split(' ').first}\'s callback as done ✓')));
                      }
                      return true;
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(AppRadius.card)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Done',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    child: AppCard(
                      onTap: () => context.push('/leads/${c.leadId}'),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          LeadAvatar(name: c.leadName, temperature: LeadTemperature.hot),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.leadName, style: t.titleSmall),
                                Text(c.note ?? 'Callback', style: t.bodySmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Icon(Icons.event_rounded, size: 18, color: AppColors.info),
                              Text(Fmt.friendlyFuture(c.scheduledAt), style: t.labelMedium?.copyWith(color: AppColors.info)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (upcoming.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Swipe left to mark as done', style: t.bodySmall),
                ),
              if (done.isNotEmpty) ...[
                const SectionLabel('Done'),
                for (final c in done.take(10))
                  ListTile(
                    leading: const Icon(Icons.check_circle_rounded, color: AppColors.success),
                    title: Text(c.leadName, style: t.titleSmall),
                    subtitle: Text(Fmt.friendlyFuture(c.scheduledAt), style: t.bodySmall),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

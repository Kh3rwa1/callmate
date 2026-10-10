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
          final upcoming = list
              .where((c) => c.status == CallbackStatus.scheduled)
              .toList();
          final done = list
              .where((c) => c.status != CallbackStatus.scheduled)
              .toList();
          if (upcoming.isEmpty && done.isEmpty) {
            return const EmptyState(
              title: 'No callbacks yet',
              message: 'Requested callbacks show up here.',
              mascot: MascotState.thinking,
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              0,
              AppSpace.page,
              32,
            ),
            children: [
              const SectionLabel(
                'Upcoming',
                padding: EdgeInsets.fromLTRB(2, 8, 2, 12),
              ),
              if (upcoming.isEmpty)
                AppCard(child: Text('All caught up', style: t.titleSmall)),
              for (final c in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey(c.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await ref.read(callbackRepoProvider).markDone(c.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Marked ${c.leadName.split(' ').first}\'s callback as done ✓',
                            ),
                          ),
                        );
                      }
                      return true;
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    child: AppCard(
                      onTap: () => context.push('/leads/${c.leadId}'),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          LeadAvatar(
                            name: c.leadName,
                            temperature: LeadTemperature.hot,
                            size: 42,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.leadName,
                                  style: t.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (c.note != null && c.note!.isNotEmpty)
                                  Text(
                                    c.note!,
                                    style: t.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            Fmt.friendlyFuture(c.scheduledAt),
                            maxLines: 1,
                            softWrap: false,
                            style: t.labelMedium?.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (upcoming.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text('Swipe left to mark done', style: t.bodySmall),
                ),
              if (done.isNotEmpty) ...[
                const SectionLabel('Done'),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, c) in done.take(10).indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(
                            Icons.check_rounded,
                            color: AppColors.success,
                          ),
                          title: Text(
                            c.leadName,
                            style: t.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            Fmt.friendlyFuture(c.scheduledAt),
                            maxLines: 1,
                            softWrap: false,
                            style: t.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

class CallbacksScreen extends ConsumerWidget {
  const CallbacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final cbs = ref.watch(callbacksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.callbacksTitle)),
      body: AsyncView<List<Callback>>(
        value: cbs,
        onRetry: () => ref.invalidate(callbacksProvider),
        data: (list) {
          final upcoming =
              list.where((c) => c.status == CallbackStatus.scheduled).toList()
                ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
          final done = list
              .where((c) => c.status != CallbackStatus.scheduled)
              .toList();
          if (upcoming.isEmpty && done.isEmpty) {
            return EmptyState(
              title: s.noCallbacksYet,
              message: s.requestedCallbacksAppear,
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
              SectionLabel(
                s.upcoming,
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
              ),
              if (upcoming.isEmpty)
                AppCard(child: Text(s.allCaughtUp, style: t.titleSmall)),
              for (final (i, c) in upcoming.indexed)
                Reveal(
                  key: ValueKey('cb-${c.id}'),
                  id: 'cb-${c.id}',
                  index: i < 8 ? i : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey(c.id),
                      direction: DismissDirection.endToStart,
                      dismissThresholds: const {
                        DismissDirection.endToStart: 0.3,
                      },
                      confirmDismiss: (_) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(callbackRepoProvider).markDone(c.id);
                        Haptics.success();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              s.markedCallbackDone(c.leadName.split(' ').first),
                            ),
                          ),
                        );
                        return true;
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: AppColors.onInverse,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s.done,
                              style: TextStyle(
                                color: AppColors.onInverse,
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
                              s.friendlyFuture(c.scheduledAt),
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
                ),
              if (upcoming.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(s.swipeLeftDone, style: t.bodySmall),
                ),
              if (done.isNotEmpty) ...[
                SectionLabel(s.done),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, c) in done.take(10).indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(
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
                            s.friendlyFuture(c.scheduledAt),
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

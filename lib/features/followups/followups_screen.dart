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
import 'whatsapp_handoff.dart';
import '../../core/widgets/brand_widgets.dart';

/// Follow-ups – "Who needs a message?"
class FollowUpsScreen extends ConsumerWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final fus = ref.watch(followUpsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<List<FollowUp>>(
          value: fus,
          onRetry: () => ref.invalidate(followUpsProvider),
          data: (all) {
            final pending = all.where((f) => f.isPending).toList();
            final opened = all.where((f) => !f.isPending).take(20).toList();
            return RefreshIndicator(
              color: AppColors.brand,
              backgroundColor: AppColors.surface,
              onRefresh: () async => ref.invalidate(followUpsProvider),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.page,
                      12,
                      AppSpace.page,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: GradientText(
                              s.followUpsTitle,
                              style: t.headlineMedium,
                            ),
                          ),
                          if (pending.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(s.followUpsSubtitle, style: t.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (pending.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: s.allCaughtUp,
                        message: s.newDraftsAppear,
                        mascot: MascotState.celebrating,
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SectionLabel(
                          s.readyToSend,
                          padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
                          trailing: PopSwitcher(
                            child: Pill(
                              key: const Key('followups-pending-count'),
                              label: '${pending.length}',
                              color: AppColors.ink,
                              background: AppColors.surfaceMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      sliver: SliverList.builder(
                        itemCount: pending.length,
                        itemBuilder: (_, i) => Reveal(
                          key: ValueKey(pending[i].id),
                          id: 'fu-${pending[i].id}',
                          index: i < 8 ? i : 0,
                          child: _FollowUpRow(
                            fu: pending[i],
                            first: i == 0,
                            last: i == pending.length - 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (pending.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.page + 2,
                          8,
                          AppSpace.page,
                          0,
                        ),
                        child: Text(s.swipeToOpenHint, style: t.bodySmall),
                      ),
                    ),
                  if (opened.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.page,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SectionLabel(s.whatsappOpened),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.page,
                        0,
                        AppSpace.page,
                        28,
                      ),
                      sliver: SliverList.builder(
                        itemCount: opened.length,
                        itemBuilder: (_, i) {
                          final f = opened[i];
                          return _Segment(
                            first: i == 0,
                            last: i == opened.length - 1,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              minTileHeight: 64,
                              onTap: () => context.push('/followups/${f.id}'),
                              leading: LeadAvatar(
                                name: f.leadName,
                                temperature: LeadTemperature.fromScore(
                                  f.scoreValue,
                                ),
                                size: 40,
                              ),
                              title: Text(
                                f.leadName,
                                style: t.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${s.followUpStatus(f.status)}${f.openedAt != null ? ' · ${s.relative(f.openedAt!)}' : ''}',
                                style: t.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ] else
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// White segment of a grouped list card (rounded at the ends, hairline
/// dividers between rows).
class _Segment extends StatelessWidget {
  const _Segment({
    required this.first,
    required this.last,
    required this.child,
  });
  final bool first;
  final bool last;
  final Widget child;

  static BorderRadius radius(bool first, bool last) {
    const r = Radius.circular(AppRadius.card);
    return BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: radius(first, last),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        if (!first) const Divider(height: 1, thickness: 1, indent: 70),
        child,
      ],
    ),
  );
}

class _FollowUpRow extends ConsumerWidget {
  const _FollowUpRow({
    required this.fu,
    required this.first,
    required this.last,
  });
  final FollowUp fu;
  final bool first;
  final bool last;

  Future<bool> _handoff(BuildContext context, WidgetRef ref) =>
      openWhatsAppHandoff(
        context,
        ref,
        phone: fu.leadPhone,
        message: fu.message,
        followUp: fu,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final temp = LeadTemperature.fromScore(fu.scoreValue);
    return Dismissible(
      key: ValueKey(fu.id),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.3},
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.whatsappFill,
          borderRadius: _Segment.radius(first, last),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'WhatsApp',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        Haptics.press();
        await _handoff(context, ref);
        return false; // list refreshes from backend state
      },
      child: _Segment(
        first: first,
        last: last,
        child: InkWell(
          onTap: () => context.push('/followups/${fu.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Hero(
                  tag: 'fu-avatar-${fu.id}',
                  child: LeadAvatar(
                    name: fu.leadName,
                    temperature: temp,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fu.leadName,
                        style: t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (fu.scoreValue != null) ...[
                            ScoreBadge(
                              score: LeadScore(
                                value: fu.scoreValue!,
                                temperature: temp,
                                intent: LeadIntent.unknown,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              s.relative(fu.createdAt),
                              style: t.bodySmall?.copyWith(
                                color: AppColors.inkFaint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        followUpPreview(fu.message),
                        style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Pressable(
                  scale: 0.9,
                  child: IconButton.filled(
                    tooltip: s.openInWhatsapp,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.whatsappSoft,
                      foregroundColor: AppColors.whatsapp,
                      fixedSize: const Size(44, 44),
                    ),
                    onPressed: () {
                      Haptics.press();
                      _handoff(context, ref);
                    },
                    icon: const Icon(Icons.chat_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A follow-up without its opening greeting ("Hi Sourav 👋 Great speaking
/// with you today."), so each list preview shows what's actually different.
String followUpPreview(String message) {
  final flat = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  final greeting = RegExp(
    r'^((hi|hello|hey|dear|namaste|namaskar)\b|नमस्ते|নমস্কার)',
    caseSensitive: false,
  );
  if (!greeting.hasMatch(flat)) return flat;
  final end = RegExp(r'[.!?।]\s').firstMatch(flat);
  if (end == null || end.end > 100) return flat;
  final rest = flat.substring(end.end).trim();
  return rest.isEmpty ? flat : rest;
}

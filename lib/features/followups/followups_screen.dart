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
import 'whatsapp_handoff.dart';

/// Follow-ups – "Who needs a message?"
class FollowUpsScreen extends ConsumerWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onRefresh: () async => ref.invalidate(followUpsProvider),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(header: true, child: Text('Follow-ups', style: t.headlineMedium)),
                          const SizedBox(height: 4),
                          Text(
                            pending.isEmpty ? 'Nothing waiting on you.' : '${pending.length} WhatsApp messages drafted from calls',
                            style: t.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (pending.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: 'All caught up 🎉',
                        message: 'New WhatsApp drafts appear here after your AI employee\'s calls.',
                        mascot: MascotState.success,
                      ),
                    )
                  else ...[
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpace.page),
                      sliver: SliverToBoxAdapter(child: SectionLabel('Ready to send')),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                      sliver: SliverList.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _FollowUpCard(fu: pending[i]),
                      ),
                    ),
                  ],
                  if (opened.isNotEmpty) ...[
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpace.page),
                      sliver: SliverToBoxAdapter(child: SectionLabel('WhatsApp opened')),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 28),
                      sliver: SliverList.builder(
                        itemCount: opened.length,
                        itemBuilder: (_, i) {
                          final f = opened[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            minTileHeight: 60,
                            onTap: () => context.push('/followups/${f.id}'),
                            leading: LeadAvatar(name: f.leadName, temperature: LeadTemperature.fromScore(f.scoreValue), size: 40),
                            title: Text(f.leadName, style: t.titleSmall),
                            subtitle: Text(
                              '${f.status.label}${f.openedAt != null ? ' · ${Fmt.relative(f.openedAt!)}' : ''}',
                              style: t.bodySmall,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
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

class _FollowUpCard extends ConsumerWidget {
  const _FollowUpCard({required this.fu});
  final FollowUp fu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final temp = LeadTemperature.fromScore(fu.scoreValue);
    return Dismissible(
      key: ValueKey(fu.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: AppColors.whatsapp, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'WhatsApp',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await openWhatsAppHandoff(context, ref, phone: fu.leadPhone, message: fu.message, followUp: fu);
        return false; // list refreshes from backend state
      },
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        onTap: () => context.push('/followups/${fu.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadAvatar(name: fu.leadName, temperature: temp, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fu.leadName, style: t.titleMedium),
                      Text('Drafted ${Fmt.relative(fu.createdAt)}', style: t.bodySmall),
                    ],
                  ),
                ),
                if (fu.scoreValue != null)
                  ScoreBadge(
                    score: LeadScore(value: fu.scoreValue!, temperature: temp, intent: LeadIntent.unknown),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.whatsappSoft, borderRadius: BorderRadius.circular(16)),
              child: Text(
                fu.message.replaceAll(RegExp(r'\n+'), ' '),
                style: t.bodyMedium?.copyWith(color: AppColors.ink),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink, alignment: Alignment.centerLeft),
                    onPressed: () => context.push('/followups/${fu.id}'),
                    child: const Text('Review'),
                  ),
                ),
                WhatsAppButton(
                  compact: true,
                  label: 'WhatsApp →',
                  onPressed: () => openWhatsAppHandoff(context, ref, phone: fu.leadPhone, message: fu.message, followUp: fu),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

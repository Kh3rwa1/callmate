import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../calls/transcript_view.dart';
import '../callbacks/callback_sheet.dart';
import '../followups/whatsapp_handoff.dart';
import 'lead_call_action.dart';
import 'lead_detail_widgets.dart';

class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.leadId});
  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lead = ref.watch(leadProvider(leadId));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<Lead>(
        value: lead,
        onRetry: () => ref.invalidate(leadProvider(leadId)),
        data: (l) => _Body(lead: l),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final l = lead;
    final calls = ref.watch(leadCallsProvider(l.id)).value ?? const <Call>[];
    final fus =
        ref
            .watch(followUpsProvider)
            .value
            ?.where((f) => f.leadId == l.id)
            .toList() ??
        const <FollowUp>[];
    final fu = fus.firstOrNull;
    final lastCall = calls.where((c) => c.status.isConnected).firstOrNull;
    final wf = ref.watch(workflowProvider);
    final agentName = ref.watch(employeeNameProvider);

    var section = 0;
    Widget reveal(Widget child) => Reveal(
      id: 'lead-detail-${l.id}-${section++}',
      index: section,
      child: child,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 36),
      children: [
        Row(
          children: [
            Hero(
              tag: 'lead-avatar-${l.id}',
              child: LeadAvatar(
                name: l.name,
                temperature: l.temperature,
                size: 64,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: t.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    PhoneUtils.display(l.phone),
                    style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  PopIn(
                    delay: const Duration(milliseconds: 180),
                    child: ScoreBadge(score: l.score, showNumber: true),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        reveal(
          Row(
            children: [
              Expanded(
                child: WhatsAppButton(
                  compact: true,
                  onPressed: () {
                    if (fu != null && fu.isPending) {
                      context.push('/followups/${fu.id}');
                    } else {
                      openWhatsAppHandoff(
                        context,
                        ref,
                        phone: l.phone,
                        message: fu?.message ?? s.waGreeting(l.firstName, ''),
                        followUp: fu,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              _ActionIcon(
                tooltip: s.aiCallTooltip,
                icon: Icons.call_outlined,
                onPressed: () => handleLeadCall(context, ref, l, agentName),
              ),
              const SizedBox(width: 10),
              _ActionIcon(
                tooltip: s.callbackTooltip,
                icon: Icons.event_outlined,
                onPressed: () => showCallbackSheet(context, ref, lead: l),
              ),
            ],
          ),
        ),
        if (l.summary != null) ...[
          SectionLabel(s.aiSummary),
          reveal(
            AppCard(
              onTap: lastCall == null
                  ? null
                  : () => context.push('/calls/${lastCall.id}/result'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 10),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          l.summary!,
                          style: t.bodyLarge,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (lastCall != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          s.fullCallResult,
                          style: t.labelMedium?.copyWith(
                            color: AppColors.brand,
                            fontSize: 14,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        SectionLabel(s.details),
        reveal(
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              children: [
                LeadDetailRow(
                  s.data(wf.interestLabel),
                  l.interest == null ? s.notKnownYet : s.data(l.interest!),
                ),
                for (final a in wf.attributes)
                  if (l.attributes[a.key] != null)
                    LeadDetailRow(
                      s.data(a.label),
                      _fmtAttr(a.key, l.attributes[a.key]!),
                    ),
                for (final e in l.attributes.entries)
                  if (!wf.attributes.any((a) => a.key == e.key))
                    LeadDetailRow(
                      s.data(_titleCase(e.key)),
                      _fmtAttr(e.key, e.value),
                    ),
                if (l.language != null)
                  LeadDetailRow(s.language, s.data(l.language!)),
                LeadDetailRow(
                  s.nextActionLabel,
                  s.nextAction(l.nextAction),
                  highlight: l.nextAction != NextAction.none,
                ),
                LeadDetailRow(
                  s.callbackLabel,
                  l.callbackAt == null
                      ? s.notScheduled
                      : s.friendlyFuture(l.callbackAt!),
                  highlight: l.callbackAt != null,
                ),
                LeadDetailRow(s.added, s.relative(l.createdAt), last: true),
              ],
            ),
          ),
        ),
        if (l.score != null &&
            (l.score!.positiveSignals.isNotEmpty ||
                l.objections.isNotEmpty)) ...[
          SectionLabel(s.signals),
          reveal(
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in l.score!.positiveSignals)
                    LeadSignalChip(text: p, positive: true),
                  for (final o in l.objections)
                    LeadSignalChip(text: o, positive: false),
                ],
              ),
            ),
          ),
        ],
        if (fu != null) ...[
          SectionLabel(
            s.followUpSection,
            trailing: Pill(
              label: s.followUpStatus(fu.status),
              color: fu.isPending ? AppColors.whatsapp : AppColors.inkSoft,
              dense: true,
            ),
          ),
          reveal(
            AppCard(
              onTap: () => context.push('/followups/${fu.id}'),
              color: AppColors.bubble,
              border: Border.all(color: AppColors.bubbleBorder),
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fu.message,
                    style: t.bodyMedium?.copyWith(color: AppColors.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        fu.isPending ? s.reviewAndSend : s.openAgain,
                        style: t.labelMedium?.copyWith(
                          color: AppColors.whatsapp,
                          fontSize: 14,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.whatsapp,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        SectionLabel(
          s.callHistory,
          trailing: Text(
            '${calls.length}',
            style: t.labelMedium?.copyWith(color: AppColors.inkFaint),
          ),
        ),
        if (calls.isEmpty)
          AppCard(
            child: Text(
              s.notCalledYet(agentName, l.firstName),
              style: t.bodyMedium,
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < calls.length; i++) ...[
                  if (i > 0) const Divider(indent: 20, endIndent: 20),
                  ListTile(
                    minTileHeight: 60,
                    onTap: () => context.push(
                      calls[i].status.isConnected
                          ? '/calls/${calls[i].id}/result'
                          : '/calls/${calls[i].id}',
                    ),
                    leading: Icon(
                      calls[i].status.isConnected
                          ? Icons.call_made_rounded
                          : Icons.phone_missed_outlined,
                      color: calls[i].status.isConnected
                          ? AppColors.success
                          : AppColors.inkFaint,
                    ),
                    title: Text(
                      calls[i].status.isConnected
                          ? s.connectedFor(Fmt.duration(calls[i].duration))
                          : s.callStatus(calls[i].status),
                      style: t.titleSmall,
                    ),
                    subtitle: Text(
                      s.friendlyFuture(calls[i].startedAt),
                      style: t.bodySmall,
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (lastCall != null && !lastCall.transcript.isEmpty) ...[
          SectionLabel(s.transcript),
          AppCard(
            child: TranscriptView(
              transcript: lastCall.transcript,
              leadName: l.firstName,
              agentName: agentName,
              maxLines: 6,
            ),
          ),
        ],
      ],
    );
  }
}

String _titleCase(String k) =>
    k.isEmpty ? k : k[0].toUpperCase() + k.substring(1).replaceAll('_', ' ');

String _fmtAttr(String key, String v) =>
    key == 'budget' && int.tryParse(v) != null ? Fmt.inr(int.parse(v)) : v;

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    scale: 0.92,
    child: IconButton.outlined(
      tooltip: tooltip,
      onPressed: () {
        Haptics.tap();
        onPressed();
      },
      style: IconButton.styleFrom(
        fixedSize: const Size(52, 48),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.border, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      icon: Icon(icon, size: 21),
    ),
  );
}

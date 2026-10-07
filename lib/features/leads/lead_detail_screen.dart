import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../calls/transcript_view.dart';
import '../callbacks/callback_sheet.dart';
import '../followups/whatsapp_handoff.dart';
import 'lead_detail_widgets.dart';
import 'lead_call_action.dart';

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 36),
      children: [
        Row(
          children: [
            LeadAvatar(name: l.name, temperature: l.temperature, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: t.headlineSmall),
                  const SizedBox(height: 4),
                  Text(PhoneUtils.display(l.phone), style: t.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ScoreBadge(score: l.score, large: true),
            Pill(label: l.status.label, color: AppColors.inkSoft),
            Pill(label: l.source, color: AppColors.info),
          ],
        ),
        const SizedBox(height: 18),
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
                      message: fu?.message ?? 'Hi ${l.firstName} 👋\n\n',
                      followUp: fu,
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => handleLeadCall(
                  context,
                  ref,
                  l,
                  ref.read(agentProvider).value?.name ?? 'Riya',
                ),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'AI Call',
                    maxLines: 1,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => showCallbackSheet(context, ref, lead: l),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Callback',
                    maxLines: 1,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (l.summary != null) ...[
          const SectionLabel('AI summary'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.summary!, style: t.bodyLarge),
                if (lastCall != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => context.push('/calls/${lastCall.id}/result'),
                    child: Text(
                      'See full call result →',
                      style: t.labelMedium?.copyWith(
                        color: AppColors.brand,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SectionLabel('Details'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(
            children: [
              LeadDetailRow(wf.interestLabel, l.interest ?? 'Not known yet'),
              for (final a in wf.attributes)
                if (l.attributes[a.key] != null)
                  LeadDetailRow(a.label, _fmtAttr(a.key, l.attributes[a.key]!)),
              for (final e in l.attributes.entries)
                if (!wf.attributes.any((a) => a.key == e.key))
                  LeadDetailRow(_titleCase(e.key), _fmtAttr(e.key, e.value)),
              if (l.language != null) LeadDetailRow('Language', l.language!),
              LeadDetailRow(
                'Next action',
                l.nextAction.label,
                highlight: l.nextAction != NextAction.none,
              ),
              LeadDetailRow(
                'Callback',
                l.callbackAt == null
                    ? 'Not scheduled'
                    : Fmt.friendlyFuture(l.callbackAt!),
                highlight: l.callbackAt != null,
              ),
              LeadDetailRow('Added', Fmt.relative(l.createdAt), last: true),
            ],
          ),
        ),
        if (l.score != null &&
            (l.score!.positiveSignals.isNotEmpty ||
                l.objections.isNotEmpty)) ...[
          const SectionLabel('Signals & objections'),
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
        ],
        if (fu != null) ...[
          SectionLabel(
            'WhatsApp follow-up',
            trailing: Pill(
              label: fu.status.label,
              color: fu.isPending ? AppColors.whatsapp : AppColors.inkSoft,
              dense: true,
            ),
          ),
          AppCard(
            onTap: () => context.push('/followups/${fu.id}'),
            color: AppColors.whatsappSoft,
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fu.message,
                  style: t.bodyMedium?.copyWith(color: AppColors.ink),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  fu.isPending ? 'Review & send →' : 'Open again →',
                  style: t.labelMedium?.copyWith(
                    color: AppColors.whatsapp,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
        SectionLabel(
          'Call history',
          trailing: Text('${calls.length}', style: t.labelMedium),
        ),
        if (calls.isEmpty)
          AppCard(
            child: Text(
              '${ref.watch(employeeNameProvider)} hasn\'t called ${l.firstName} yet.',
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
                          ? Icons.check_circle_rounded
                          : Icons.phone_missed_rounded,
                      color: calls[i].status.isConnected
                          ? AppColors.success
                          : AppColors.inkFaint,
                    ),
                    title: Text(
                      calls[i].status.isConnected
                          ? 'Connected · ${Fmt.duration(calls[i].duration)}'
                          : calls[i].status.label,
                      style: t.titleSmall,
                    ),
                    subtitle: Text(
                      Fmt.friendlyFuture(calls[i].startedAt),
                      style: t.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ],
            ),
          ),
        if (lastCall != null && !lastCall.transcript.isEmpty) ...[
          const SectionLabel('Latest transcript'),
          AppCard(
            child: TranscriptView(
              transcript: lastCall.transcript,
              leadName: l.firstName,
              agentName: ref.watch(employeeNameProvider),
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

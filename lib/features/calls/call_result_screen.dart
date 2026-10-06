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
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../callbacks/callback_sheet.dart';
import 'transcript_view.dart';

/// Post-call result – the "AI understood" moment.
class CallResultScreen extends ConsumerWidget {
  const CallResultScreen({super.key, required this.callId, this.detailOnly = false});
  final String callId;
  final bool detailOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider(callId));
    return Scaffold(
      appBar: AppBar(title: Text(detailOnly ? 'Call details' : '')),
      body: AsyncView<Call>(
        value: call,
        onRetry: () => ref.invalidate(callProvider(callId)),
        data: (c) => c.status.isConnected && !detailOnly ? _Result(call: c) : _Detail(call: c),
      ),
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result({required this.call});
  final Call call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = call;
    final score = c.leadScore;
    final hot = c.isHot;
    final fuId = c.followUpId;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Call completed ✓', style: t.headlineMedium),
                        const SizedBox(height: 6),
                        Text(c.leadName, style: t.titleLarge?.copyWith(color: AppColors.inkSoft)),
                        const SizedBox(height: 4),
                        Text('${Fmt.friendlyFuture(c.startedAt)} · ${Fmt.duration(c.duration)}', style: t.bodySmall),
                      ],
                    ),
                  ),
                  Mascot(state: hot ? MascotState.hotLead : MascotState.success, size: 110),
                ],
              ),
              const SectionLabel('AI summary'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text('What Riya understood', style: t.labelMedium?.copyWith(color: AppColors.brand)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('“${c.summary ?? 'No summary available.'}”', style: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5)),
                    if ((c.courseInterest ?? '').isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Pill(label: '🎓 ${c.courseInterest}', color: AppColors.ink, background: AppColors.surfaceMuted),
                          if (c.transcript.language != null)
                            Pill(label: '🗣 ${c.transcript.language}', color: AppColors.ink, background: AppColors.surfaceMuted),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (score != null) ...[
                const SectionLabel('Lead score'),
                AppCard(
                  color: hot ? AppColors.hotSoft : Colors.white,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ScoreRing(score: score, size: 120),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${TempStyle.of(score.temperature).emoji} ${score.value} / 100', style: t.headlineSmall),
                                const SizedBox(height: 4),
                                Text(
                                  score.intentLabel,
                                  style: t.labelLarge?.copyWith(color: TempStyle.of(score.temperature).fg, letterSpacing: 1),
                                ),
                                const SizedBox(height: 6),
                                Text(score.intent.label, style: t.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (score.positiveSignals.isNotEmpty || score.concerns.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 10),
                        for (final p in score.positiveSignals) _Reason(text: p, positive: true),
                        if (score.positiveSignals.isNotEmpty && score.concerns.isNotEmpty) const SizedBox(height: 6),
                        for (final o in score.concerns) _Reason(text: o, positive: false),
                      ],
                    ],
                  ),
                ),
              ],
              const SectionLabel('Recommended action'),
              AppCard(
                child: Row(
                  children: [
                    const IconBubble(color: AppColors.infoSoft, child: Emoji('📅')),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.callbackAt != null ? 'Call ${Fmt.callbackPhrase(c.callbackAt!)}' : c.nextAction.label,
                            style: t.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(c.nextAction.label, style: t.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!c.transcript.isEmpty) ...[
                const SectionLabel('Transcript'),
                AppCard(
                  child: TranscriptView(transcript: c.transcript, leadName: c.leadName.split(' ').first, maxLines: 4),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 12),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SecondaryButton(
                    label: 'Schedule Callback',
                    onPressed: () async {
                      final lead = await ref.read(leadRepoProvider).get(c.leadId);
                      if (context.mounted) await showCallbackSheet(context, ref, lead: lead, suggested: c.callbackAt);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: PrimaryButton(
                    label: 'Send WhatsApp',
                    icon: Icons.chat_rounded,
                    color: AppColors.whatsapp,
                    onPressed: fuId == null ? () => context.push('/leads/${c.leadId}') : () => context.push('/followups/$fuId'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.text, required this.positive});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(positive ? '✅' : '⚠️', style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// For not-connected calls (or explicit detail view).
class _Detail extends StatelessWidget {
  const _Detail({required this.call});
  final Call call;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = call;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
      children: [
        Center(child: Mascot(state: c.status.isConnected ? MascotState.success : MascotState.error, size: 140)),
        const SizedBox(height: 12),
        Center(child: Text(c.leadName, style: t.headlineSmall)),
        Center(child: Text(PhoneUtils.display(c.leadPhone), style: t.bodyMedium)),
        const SizedBox(height: 18),
        AppCard(
          child: Column(
            children: [
              _kv(t, 'Status', c.status.label),
              _kv(t, 'When', Fmt.friendlyFuture(c.startedAt)),
              if (c.status.isConnected) _kv(t, 'Duration', Fmt.duration(c.duration)),
              _kv(t, 'Outcome', c.outcome ?? '—'),
              _kv(t, 'Next', c.nextAction.label),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!c.status.isConnected)
          Text(
            'Riya will try again in the next campaign. You can also call them yourself.',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        SecondaryButton(label: 'Open lead', onPressed: () => context.push('/leads/${c.leadId}')),
      ],
    );
  }

  Widget _kv(TextTheme t, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(k, style: t.bodyMedium)),
        Expanded(child: Text(v, style: t.titleSmall)),
      ],
    ),
  );
}

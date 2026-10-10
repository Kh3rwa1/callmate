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
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../callbacks/callback_sheet.dart';
import 'transcript_view.dart';

/// Post-call result – the "AI understood" moment.
class CallResultScreen extends ConsumerWidget {
  const CallResultScreen({
    super.key,
    required this.callId,
    this.detailOnly = false,
  });
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
        data: (c) => c.status.isConnected && !detailOnly
            ? _Result(call: c)
            : _Detail(call: c),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              0,
              AppSpace.page,
              24,
            ),
            children: [
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(
                  c.leadName,
                  style: t.headlineMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${Fmt.friendlyFuture(c.startedAt)} · ${Fmt.duration(c.duration)}',
                      style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: AppColors.brand,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'What ${ref.watch(employeeNameProvider)} understood',
                            style: t.labelMedium?.copyWith(
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '“${c.summary ?? 'No summary available.'}”',
                      style: t.bodyLarge?.copyWith(height: 1.45),
                    ),
                    if ((c.interest ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Pill(
                            label: c.interest!,
                            color: AppColors.ink,
                            background: AppColors.surfaceMuted,
                            icon: const Icon(
                              Icons.push_pin_outlined,
                              size: 14,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          if (c.transcript.language != null)
                            Pill(
                              label: c.transcript.language!,
                              color: AppColors.ink,
                              background: AppColors.surfaceMuted,
                              icon: const Icon(
                                Icons.translate_rounded,
                                size: 14,
                                color: AppColors.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (score != null) ...[
                const SectionLabel('Lead score'),
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              ScoreRing(score: score, size: 112),
                              if (hot)
                                const Positioned(
                                  left: -54,
                                  top: -54,
                                  child: ConfettiBurst(size: 220),
                                ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${TempStyle.of(score.temperature).word} lead',
                                  style: t.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  score.intent.label,
                                  style: t.bodyMedium?.copyWith(
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (score.positiveSignals.isNotEmpty ||
                          score.concerns.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        for (final p in score.positiveSignals)
                          _Reason(text: p, positive: true),
                        for (final o in score.concerns)
                          _Reason(text: o, positive: false),
                      ],
                    ],
                  ),
                ),
              ],
              const SectionLabel('Next step'),
              AppCard(
                child: Row(
                  children: [
                    const IconBubble(
                      color: AppColors.surfaceMuted,
                      size: 44,
                      child: Emoji('🤝', size: 21),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _actionTitle(c.nextAction),
                            style: t.titleMedium,
                          ),
                          if (c.callbackAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Call back ${Fmt.callbackPhrase(c.callbackAt!)}',
                              style: t.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!c.transcript.isEmpty) ...[
                const SectionLabel('Transcript'),
                AppCard(
                  child: TranscriptView(
                    transcript: c.transcript,
                    leadName: c.leadName.split(' ').first,
                    agentName: ref.watch(employeeNameProvider),
                    maxLines: 4,
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              12,
              AppSpace.page,
              12,
            ),
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
                      final lead = await ref
                          .read(leadRepoProvider)
                          .get(c.leadId);
                      if (context.mounted) {
                        await showCallbackSheet(
                          context,
                          ref,
                          lead: lead,
                          suggested: c.callbackAt,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: PrimaryButton(
                    label: 'Prepare WhatsApp',
                    icon: Icons.chat_bubble_outline_rounded,
                    onPressed: fuId == null
                        ? () => context.push('/leads/${c.leadId}')
                        : () => context.push('/followups/$fuId'),
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

/// Owner-facing phrasing of the AI's structured next action.
String _actionTitle(NextAction a) => switch (a) {
  NextAction.whatsappAndCallback ||
  NextAction.humanFollowUp => 'Human follow-up',
  NextAction.sendWhatsapp => 'Send a WhatsApp follow-up',
  NextAction.bookAppointment => 'Book an appointment / visit',
  NextAction.retryCall => 'Try calling again',
  NextAction.none => 'No action needed',
};

class _Reason extends StatelessWidget {
  const _Reason({required this.text, required this.positive});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(
          positive
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          size: 18,
          color: positive ? AppColors.success : AppColors.warmInk,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
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
    final rows = <(String, String)>[
      ('Status', c.status.label),
      ('When', Fmt.friendlyFuture(c.startedAt)),
      if (c.status.isConnected) ('Duration', Fmt.duration(c.duration)),
      ('Outcome', c.outcome ?? '—'),
      ('Next', c.nextAction.label),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 32),
      children: [
        Center(
          child: Mascot(
            state: c.status.isConnected
                ? MascotState.success
                : MascotState.error,
            size: 96,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            c.leadName,
            style: t.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            PhoneUtils.display(c.leadPhone),
            style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
          ),
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _kv(t, rows[i].$1, rows[i].$2),
              ],
            ],
          ),
        ),
        if (!c.status.isConnected) ...[
          const SizedBox(height: 16),
          Text(
            'Your AI employee will try again in the next campaign.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        SecondaryButton(
          label: 'Open lead',
          onPressed: () => context.push('/leads/${c.leadId}'),
        ),
      ],
    );
  }

  Widget _kv(TextTheme t, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: t.bodyMedium?.copyWith(color: AppColors.inkFaint)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            v,
            style: t.titleSmall,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

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
import '../../l10n/l10n.dart';
import '../callbacks/callback_sheet.dart';
import 'transcript_view.dart';

/// Post-call result – the "AI understood" moment.
///
/// Choreography: the name lands, the summary appears word by word, the
/// score ring sweeps and counts up (confetti for a hot lead), then the next
/// step and the transcript follow.
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
    final s = context.s;
    final call = ref.watch(callProvider(callId));
    return Scaffold(
      appBar: AppBar(title: Text(detailOnly ? s.callDetails : '')),
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
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final c = call;
    final score = c.leadScore;
    final hot = c.isHot;
    final fuId = c.followUpId;
    final agentName = ref.watch(employeeNameProvider);

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
              Reveal(
                child: Semantics(
                  header: true,
                  child: Text(
                    c.leadName,
                    style: t.headlineMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Reveal(
                index: 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${s.friendlyFuture(c.startedAt)} · ${Fmt.duration(c.duration)}',
                        style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Reveal(
                index: 2,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: AppColors.brand,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              s.whatUnderstood(agentName),
                              style: t.labelMedium?.copyWith(
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      WordReveal(
                        '“${c.summary ?? s.noSummary}”',
                        style: t.bodyLarge?.copyWith(height: 1.45),
                      ),
                      if ((c.interest ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            PopIn(
                              delay: const Duration(milliseconds: 500),
                              child: Pill(
                                label: s.data(c.interest!),
                                color: AppColors.ink,
                                background: AppColors.surfaceMuted,
                                icon: Icon(
                                  Icons.push_pin_outlined,
                                  size: 14,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                            if (c.transcript.language != null)
                              PopIn(
                                delay: const Duration(milliseconds: 580),
                                child: Pill(
                                  label: s.data(c.transcript.language!),
                                  color: AppColors.ink,
                                  background: AppColors.surfaceMuted,
                                  icon: Icon(
                                    Icons.translate_rounded,
                                    size: 14,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (score != null) ...[
                Reveal(index: 3, child: SectionLabel(s.leadScoreTitle)),
                Reveal(
                  index: 4,
                  child: AppCard(
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
                                    s.temperature(score.temperature),
                                    style: t.headlineSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.intent(score.intent),
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
                          for (final (i, p) in score.positiveSignals.indexed)
                            Reveal(
                              index: 6 + i,
                              offset: 6,
                              child: _Reason(text: p, positive: true),
                            ),
                          for (final (i, o) in score.concerns.indexed)
                            Reveal(
                              index: 6 + score.positiveSignals.length + i,
                              offset: 6,
                              child: _Reason(text: o, positive: false),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              Reveal(index: 5, child: SectionLabel(s.nextStep)),
              Reveal(
                index: 6,
                child: AppCard(
                  child: Row(
                    children: [
                      IconBubble(
                        color: AppColors.brandSoft,
                        size: 44,
                        child: Icon(
                          _actionIcon(c.nextAction),
                          size: 21,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.nextAction(c.nextAction),
                              style: t.titleMedium,
                            ),
                            if (c.callbackAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                s.callBackAt(s.callbackPhrase(c.callbackAt!)),
                                style: t.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!c.transcript.isEmpty) ...[
                SectionLabel(s.transcript),
                AppCard(
                  child: TranscriptView(
                    transcript: c.transcript,
                    leadName: c.leadName.split(' ').first,
                    agentName: agentName,
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
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SecondaryButton(
                    label: s.scheduleCallback,
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
                  child: fuId == null
                      ? PrimaryButton(
                          label: s.openLead,
                          icon: Icons.person_outline_rounded,
                          onPressed: () => context.push('/leads/${c.leadId}'),
                        )
                      : PrimaryButton(
                          label: s.prepareWhatsapp,
                          icon: Icons.chat_bubble_outline_rounded,
                          color: AppColors.whatsappFill,
                          onPressed: () => context.push('/followups/$fuId'),
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

IconData _actionIcon(NextAction a) => switch (a) {
  NextAction.humanFollowUp => Icons.support_agent_rounded,
  NextAction.sendWhatsapp => Icons.chat_bubble_outline_rounded,
  NextAction.whatsappAndCallback => Icons.forum_outlined,
  NextAction.bookAppointment => Icons.event_available_outlined,
  NextAction.retryCall => Icons.replay_rounded,
  NextAction.none => Icons.check_rounded,
};

class _Reason extends StatelessWidget {
  const _Reason({required this.text, required this.positive});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final c = call;
    final rows = <(String, String)>[
      (s.status, s.callStatus(c.status)),
      (s.when, s.friendlyFuture(c.startedAt)),
      if (c.status.isConnected) (s.durationLabel, Fmt.duration(c.duration)),
      (s.outcome, c.outcome ?? '—'),
      (s.nextLabel, s.nextAction(c.nextAction)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 32),
      children: [
        Center(
          child: PopIn(
            child: Mascot(
              state: c.status.isConnected
                  ? MascotState.celebrating
                  : MascotState.thinking,
              pose: c.status.isConnected ? null : BirdPose.error,
              size: 96,
            ),
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
        Reveal(
          child: AppCard(
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
        ),
        if (!c.status.isConnected) ...[
          const SizedBox(height: 16),
          Text(
            s.willRetryNextCampaign,
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        SecondaryButton(
          label: s.openLead,
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

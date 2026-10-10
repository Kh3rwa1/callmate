import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../usage/billing_actions.dart' show externalUrlLauncherProvider;

/// mailto: link asking support to customise [playbook].
Uri playbookCustomiseUri(S s, CallPlaybook playbook) => Uri(
  scheme: 'mailto',
  path: AppEnv.supportEmail,
  query:
      'subject=${Uri.encodeComponent(s.playbookCustomiseSubject(playbook.name))}',
);

/// "Your call playbook": the questions the AI asks, what ready-to-buy means,
/// objection hints, the default WhatsApp follow-ups and callback timing for
/// the business's vertical. Read-only (v1); changes go through support.
class PlaybookScreen extends ConsumerWidget {
  const PlaybookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final provider = playbookProvider(s.lang.code);
    return Scaffold(
      appBar: AppBar(title: Text(s.playbookTitle)),
      body: AsyncView<CallPlaybook>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (p) => _Body(p),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.p);
  final CallPlaybook p;

  Future<void> _customise(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    Haptics.tap();
    var ok = false;
    try {
      ok = await ref.read(externalUrlLauncherProvider)(
        playbookCustomiseUri(s, p),
      );
    } catch (_) {}
    if (!ok) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.playbookMailFailed(AppEnv.supportEmail))),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final soft = t.bodyMedium?.copyWith(color: AppColors.inkSoft);
    var i = 0;
    Widget reveal(Widget child) =>
        Reveal(id: 'playbook-section-${i++}', index: i, child: child);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 40),
      children: [
        reveal(
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_rounded, color: AppColors.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.playbookOf(p.name),
                        key: const ValueKey('playbook-name'),
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(s.playbookIntro, style: soft),
              ],
            ),
          ),
        ),
        SectionLabel(s.playbookQuestions),
        reveal(
          CardGroup(
            children: [
              for (final (n, q) in p.qualifyingQuestions.indexed)
                _NumberedRow(number: n + 1, text: q),
            ],
          ),
        ),
        SectionLabel(s.playbookReadyToBuy),
        reveal(
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.readyToBuy, style: t.bodyLarge),
                const SizedBox(height: 8),
                Text(s.playbookReadyScore(p.minScore), style: soft),
              ],
            ),
          ),
        ),
        if (p.objections.isNotEmpty) ...[
          SectionLabel(s.playbookObjections),
          reveal(
            CardGroup(
              children: [
                for (final o in p.objections)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('“${o.objection}”', style: t.titleSmall),
                        const SizedBox(height: 4),
                        Text(o.hint, style: soft),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        SectionLabel(s.playbookFollowups),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(s.playbookFollowupsNote, style: soft),
        ),
        reveal(
          CardGroup(
            children: [
              for (final o in FollowupOutcome.values)
                if (p.followupTemplates.containsKey(o))
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.followupOutcome(o),
                          style: t.labelLarge?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.preview(
                            o,
                            namePlaceholder: s.playbookNamePlaceholder,
                          ),
                          key: ValueKey('followup-${o.wire}'),
                          style: t.bodyMedium,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        if (p.callbackHint.isNotEmpty) ...[
          SectionLabel(s.playbookCallbackTiming),
          reveal(
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule_rounded, color: AppColors.inkSoft),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.callbackHint, style: t.bodyMedium)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(s.playbookCustomiseHint, style: soft),
        const SizedBox(height: 12),
        SecondaryButton(
          label: s.playbookCustomise,
          icon: Icons.mail_outline_rounded,
          onPressed: () => _customise(context, ref),
        ),
      ],
    );
  }
}

class _NumberedRow extends StatelessWidget {
  const _NumberedRow({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.surfaceMuted,
            child: Text(
              '$number',
              style: t.labelMedium?.copyWith(color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: t.bodyMedium)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/call_forwarding.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../usage/billing_actions.dart';

/// "Who answers my calls": the AI employee answers every call, only the ones
/// the owner misses, or none. The phone does the forwarding; the app gives
/// the codes for the owner's network (`/agent/answering`).
class AnsweringScreen extends ConsumerWidget {
  const AnsweringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.answeringTitle)),
      body: AsyncView<AnsweringInfo>(
        value: ref.watch(answeringProvider),
        onRetry: () => ref.invalidate(answeringProvider),
        data: (a) => _Body(a),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body(this.info);
  final AnsweringInfo info;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  AnswerMode? _saving;
  ForwardingNetwork? _network;

  @override
  void initState() {
    super.initState();
    _network = switch (ref.read(localPrefsProvider).forwardingNetwork) {
      'jio' => ForwardingNetwork.jio,
      'gsm' => ForwardingNetwork.gsm,
      _ => null,
    };
  }

  Future<void> _choose(AnswerMode mode) async {
    if (_saving != null || mode == widget.info.mode) return;
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = mode);
    Haptics.tap();
    try {
      await ref.read(callRepoProvider).setAnswering(mode);
      ref.invalidate(answeringProvider);
    } catch (e) {
      final message = e is ApiException && e.code == 'no_numbers'
          ? s.answeringNoNumbers
          : friendlyError(e, s);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  void _pickNetwork(ForwardingNetwork n) {
    Haptics.tap();
    setState(() => _network = n);
    ref.read(localPrefsProvider).setForwardingNetwork(n.name);
  }

  Future<void> _dial(String code) async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    Haptics.tap();
    var ok = false;
    try {
      // '#' must be percent-encoded in a tel: URI or the dialer drops it.
      ok = await ref.read(externalUrlLauncherProvider)(
        Uri(scheme: 'tel', path: code),
      );
    } catch (_) {}
    if (!ok) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.dialYourself(code))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final a = widget.info;
    final agentName = ref.watch(agentProvider).value?.name ?? 'AI';
    final line = a.phone;
    final mode = _saving ?? a.mode;

    Widget option(AnswerMode m, String title, String subtitle) =>
        RadioListTile<AnswerMode>(
          key: Key('answer-mode-${m.name}'),
          value: m,
          enabled: _saving == null,
          title: Text(title, style: t.titleSmall),
          subtitle: Text(subtitle, style: t.bodySmall),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 40),
      children: [
        Text(s.answeringIntro(agentName), style: t.bodyLarge),
        const SizedBox(height: 8),
        if (!a.available && !a.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              child: Text(s.answeringUnavailable, style: t.bodyMedium),
            ),
          )
        else if (!a.hasNumber)
          // Forwarding goes to the business number: no number, nothing to set.
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              key: const Key('answering-needs-number'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.answeringNeedsNumber, style: t.bodyMedium),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.push('/agent/number'),
                    child: Text(s.getBusinessNumber),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SectionLabel(s.whoAnswers),
          RadioGroup<AnswerMode>(
            groupValue: mode,
            onChanged: (v) => _choose(v!),
            child: CardGroup(
              children: [
                option(AnswerMode.ai, s.modeAi(agentName), s.modeAiSub),
                option(
                  AnswerMode.missed,
                  s.modeMissed(agentName),
                  s.modeMissedSub,
                ),
                option(
                  AnswerMode.owner,
                  s.modeOwner,
                  s.modeOwnerSub(agentName),
                ),
              ],
            ),
          ),
        ],
        if (line != null && _saving == null) ...[
          SectionLabel(s.applyOnPhone),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.answeringLine, style: t.bodySmall),
                const SizedBox(height: 2),
                // Plain digits: the display serif is hard to read in a number.
                SelectableText(
                  PhoneUtils.display(line),
                  key: const Key('answering-line'),
                  style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                Text(s.whichNetwork, style: t.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('network-jio'),
                      label: const Text('Jio'),
                      selected: _network == ForwardingNetwork.jio,
                      onSelected: (_) => _pickNetwork(ForwardingNetwork.jio),
                    ),
                    ChoiceChip(
                      key: const Key('network-gsm'),
                      label: Text(s.networkOthers),
                      selected: _network == ForwardingNetwork.gsm,
                      onSelected: (_) => _pickNetwork(ForwardingNetwork.gsm),
                    ),
                  ],
                ),
                if (_network != null) ...[
                  const SizedBox(height: 12),
                  Text(s.answeringForwardHint, style: t.bodyMedium),
                ],
              ],
            ),
          ),
          if (_network != null) ...[
            const SizedBox(height: 12),
            CardGroup(
              children: [
                for (final (i, step) in forwardingSteps(
                  mode,
                  _network!,
                  line,
                ).indexed)
                  _StepRow(
                    number: i + 1,
                    title: s.forwardingStep(step.kind, agentName),
                    code: step.code,
                    onTap: _dial,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              s.answeringChargesNote,
              style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.code,
    required this.onTap,
  });
  final int number;
  final String title;
  final String code;
  final void Function(String code) onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      key: Key('forward-step-$number'),
      minTileHeight: 64,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: AppColors.surfaceMuted,
        child: Text('$number', style: t.labelLarge),
      ),
      title: Text(title, style: t.titleSmall),
      subtitle: Text(code, style: t.bodySmall),
      trailing: Icon(Icons.dialpad_rounded, color: AppColors.brand),
      onTap: () => onTap(code),
    );
  }
}

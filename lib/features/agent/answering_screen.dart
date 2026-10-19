import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../usage/billing_actions.dart';

/// GSM call-forwarding codes the owner dials once to send calls to their AI
/// line: when unanswered, busy or unreachable, and to cancel all of them.
abstract final class ForwardingCodes {
  static String noAnswer(String line) => '**61*$line#';
  static String busy(String line) => '**67*$line#';
  static String unreachable(String line) => '**62*$line#';
  static const stopAll = '##002#';
}

/// "Answer my missed calls": the AI picks up calls the owner can't, on a
/// number their phone forwards to (`/agent/answering`).
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
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    Haptics.tap();
    try {
      await ref.read(callRepoProvider).setAnswering(on);
      ref.invalidate(answeringProvider);
    } catch (e) {
      final message = e is ApiException && e.code == 'no_numbers'
          ? s.answeringNoNumbers
          : friendlyError(e, s);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 40),
      children: [
        Text(s.answeringIntro(agentName), style: t.bodyLarge),
        const SizedBox(height: 20),
        if (!a.available && !a.enabled)
          AppCard(child: Text(s.answeringUnavailable, style: t.bodyMedium))
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const Key('answering-switch'),
              value: a.enabled,
              onChanged: _busy ? null : _toggle,
              title: Text(s.answeringSwitch(agentName), style: t.titleSmall),
            ),
          ),
        if (line != null) ...[
          SectionLabel(s.answeringForwardTitle(agentName)),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.answeringLine, style: t.bodySmall),
                const SizedBox(height: 2),
                SelectableText(
                  PhoneUtils.display(line),
                  key: const Key('answering-line'),
                  style: t.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(s.answeringForwardHint, style: t.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardGroup(
            children: [
              _ForwardRow(
                icon: Icons.phone_missed_outlined,
                title: s.forwardNoAnswer,
                code: ForwardingCodes.noAnswer(line),
                onTap: _dial,
              ),
              _ForwardRow(
                icon: Icons.phone_in_talk_outlined,
                title: s.forwardBusy,
                code: ForwardingCodes.busy(line),
                onTap: _dial,
              ),
              _ForwardRow(
                icon: Icons.signal_cellular_off_outlined,
                title: s.forwardUnreachable,
                code: ForwardingCodes.unreachable(line),
                onTap: _dial,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _dial(ForwardingCodes.stopAll),
              icon: const Icon(Icons.phone_disabled_outlined),
              label: Text(s.forwardStop),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.answeringChargesNote,
            style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ],
    );
  }
}

class _ForwardRow extends StatelessWidget {
  const _ForwardRow({
    required this.icon,
    required this.title,
    required this.code,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String code;
  final void Function(String code) onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      minTileHeight: 64,
      leading: Icon(icon, color: AppColors.ink),
      title: Text(title, style: t.titleSmall),
      subtitle: Text(code, style: t.bodySmall),
      trailing: Icon(Icons.dialpad_rounded, color: AppColors.brand),
      onTap: () => onTap(code),
    );
  }
}

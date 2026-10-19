import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

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
import '../usage/billing_sheets.dart';

/// "Your business number": one fixed number for the business, chosen once.
/// It is the caller ID of every AI call, and customers who call it back reach
/// the AI employee. Comes with every paid plan (`/business-number`).
class BusinessNumberScreen extends ConsumerWidget {
  const BusinessNumberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.businessNumberTitle)),
      body: AsyncView<BusinessNumberInfo>(
        value: ref.watch(businessNumberProvider),
        onRetry: () => ref.invalidate(businessNumberProvider),
        data: (info) => _Body(info),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body(this.info);
  final BusinessNumberInfo info;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  String? _picked;
  bool _busy = false;

  Future<void> _upgrade() async {
    final usage = await ref.read(usageProvider.future);
    if (!mounted) return;
    Haptics.tap();
    final outcome = await showPlanPickerSheet(context, usage);
    if (outcome != null) ref.invalidate(businessNumberProvider);
  }

  Future<void> _request() async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(callRepoProvider).requestNumber();
      Haptics.success();
      ref.invalidate(businessNumberProvider);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rent(String phone) async {
    final s = context.s;
    final agent = ref.read(agentProvider).value?.name ?? 'AI';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.rentNumberConfirmTitle(PhoneUtils.display(phone))),
        content: Text(s.rentNumberConfirmBody(agent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(s.cancel),
          ),
          TextButton(
            key: const Key('rent-number-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.rentNumberYes),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(callRepoProvider).rentNumber(phone);
      Haptics.success();
      ref
        ..invalidate(businessNumberProvider)
        ..invalidate(answeringProvider);
    } catch (e) {
      final message = switch (e) {
        ApiException(code: 'number_taken') => s.numberTaken,
        ApiException(code: 'not_entitled') => s.numberNeedsPaidPlan,
        _ => friendlyError(e, s),
      };
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      if (e is ApiException && e.code == 'number_taken') {
        setState(() => _picked = null);
        ref.invalidate(businessNumberProvider);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final info = widget.info;
    final agent = ref.watch(agentProvider).value?.name ?? 'AI';
    final number = info.number;

    final List<Widget> children;
    if (number != null) {
      children = [_NumberCard(number: number, agent: agent, onRenew: _upgrade)];
    } else if (!info.available) {
      children = [
        AppCard(child: Text(s.answeringUnavailable, style: t.bodyMedium)),
      ];
    } else if (!info.entitled) {
      children = [
        _Why(agent: agent),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('number-upgrade'),
          onPressed: _upgrade,
          icon: const Icon(Icons.workspace_premium_rounded),
          label: Text(s.numberGetWithPlan),
        ),
        const SizedBox(height: 8),
        Text(
          s.numberIncludedInPlans,
          style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          textAlign: TextAlign.center,
        ),
      ];
    } else if (info.numbersFree.isEmpty) {
      // None free: numbers are bought for the business on request.
      children = [
        _Why(agent: agent),
        const SizedBox(height: 16),
        if (info.requested)
          AppCard(
            key: const Key('number-requested'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.numberRequestedTitle, style: t.titleSmall),
                      const SizedBox(height: 4),
                      Text(s.numberRequestedBody(agent), style: t.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          AppCard(child: Text(s.numberNoneFree, style: t.bodyMedium)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('number-request'),
            onPressed: _busy ? null : _request,
            child: Text(s.requestMyNumber),
          ),
        ],
      ];
    } else {
      children = [
        _Why(agent: agent),
        SectionLabel(s.pickYourNumber),
        RadioGroup<String>(
          groupValue: _picked,
          onChanged: (v) => setState(() => _picked = v),
          child: CardGroup(
            children: [
              for (final n in info.numbersFree)
                RadioListTile<String>(
                  key: Key('number-option-$n'),
                  value: n,
                  enabled: !_busy,
                  title: Text(
                    PhoneUtils.display(n),
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('rent-number'),
          onPressed: _picked == null || _busy ? null : () => _rent(_picked!),
          child: Text(s.rentThisNumber),
        ),
        const SizedBox(height: 8),
        Text(
          s.numberChosenOnce(info.holdDays),
          style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          textAlign: TextAlign.center,
        ),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 40),
      children: children,
    );
  }
}

/// What the number does for the business.
class _Why extends StatelessWidget {
  const _Why({required this.agent});
  final String agent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: t.bodyMedium)),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.numberWhyTitle, style: t.titleMedium),
          const SizedBox(height: 8),
          point(Icons.badge_outlined, s.numberWhySame(agent)),
          point(Icons.phone_callback_outlined, s.numberWhyCallBack(agent)),
          point(Icons.lock_outline_rounded, s.numberWhyYours),
        ],
      ),
    );
  }
}

/// The rented number: big, copyable, shareable; on hold after a lapse.
class _NumberCard extends ConsumerWidget {
  const _NumberCard({
    required this.number,
    required this.agent,
    required this.onRenew,
  });
  final BusinessNumber number;
  final String agent;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final display = PhoneUtils.display(number.phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.yourBusinessNumber, style: t.bodySmall),
                  ),
                  _StatusChip(held: number.held),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                display,
                key: const Key('business-number'),
                style: t.headlineSmall?.copyWith(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                number.held
                    ? s.numberHeldUntil(
                        s.date(number.heldUntil ?? DateTime.now()),
                      )
                    : s.numberActiveNote(agent),
                style: t.bodyMedium,
              ),
              if (number.held) ...[
                const SizedBox(height: 8),
                Text(
                  s.numberHeldForwarding,
                  key: const Key('number-held-forwarding'),
                  style: t.bodySmall?.copyWith(color: AppColors.warmInk),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: display));
                      Haptics.tap();
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(content: Text(s.copied)));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(s.copyNumber),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: s.shareNumberText(display)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(s.shareLink),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (number.held)
          FilledButton(onPressed: onRenew, child: Text(s.renewToKeepNumber))
        else
          CardGroup(
            children: [
              ListTile(
                minTileHeight: 60,
                key: const Key('number-forward-own-phone'),
                leading: const Icon(Icons.phone_callback_outlined),
                title: Text(s.forwardYourPhone, style: t.titleSmall),
                subtitle: Text(s.forwardYourPhoneHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/agent/answering'),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.held});
  final bool held;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (fg, bg) = held
        ? (AppColors.warmInk, AppColors.warmSoft)
        : (AppColors.success, AppColors.successSoft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        held ? s.numberOnHold : s.numberActive,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

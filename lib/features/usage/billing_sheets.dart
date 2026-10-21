import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'billing_actions.dart';

/// Plan picker: Starter / Growth, monthly or yearly ("1 month free"), with
/// the GST breakdown. Returns the checkout outcome when the payment page
/// opened, the (mock) payment went through or a UPI payment's UTR was sent;
/// errors stay inside the sheet.
Future<CheckoutOutcome?> showPlanPickerSheet(BuildContext context, Usage u) =>
    showModalBottomSheet<CheckoutOutcome>(
      useRootNavigator: true,
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(usage: u, topup: false),
    );

/// "Buy more minutes": top-up packs for an active plan.
Future<CheckoutOutcome?> showTopupSheet(BuildContext context, Usage u) =>
    showModalBottomSheet<CheckoutOutcome>(
      useRootNavigator: true,
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(usage: u, topup: true),
    );

/// mailto: link asking support to upgrade [business] to [plan], used while
/// online payments are not set up.
Uri upgradeEmailUri(S s, CheckoutPlan plan, Business? business) => Uri(
  scheme: 'mailto',
  path: AppEnv.supportEmail,
  query:
      'subject=${Uri.encodeComponent(s.upgradeEmailSubject(plan.name))}'
      '&body=${Uri.encodeComponent(s.upgradeEmailBody(plan.name, Fmt.inr(plan.totalInr), business == null ? '-' : '${business.name} (${business.id})'))}',
);

/// GST percentage for labels, e.g. 18.
String gstPercent(CheckoutPlan p) =>
    p.priceInr == 0 ? '18' : ((p.gstInr / p.priceInr) * 100).round().toString();

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet({required this.usage, required this.topup});
  final Usage usage;
  final bool topup;
  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  late bool _yearly;
  late String _selected;
  bool _busy = false;
  String? _error;

  /// Checkout said online payments aren't set up: offer "Email us" instead of paying.
  bool _byEmail = false;

  /// Checkout asked for a UPI payment: the sheet shows how to pay it.
  UpiCheckout? _upi;

  List<CheckoutPlan> get _options {
    final u = widget.usage;
    if (widget.topup) return u.topups;
    return u.plans.where((p) => p.isAnnual == _yearly).toList();
  }

  @override
  void initState() {
    super.initState();
    final u = widget.usage;
    _yearly = u.subscription.annual;
    if (widget.topup) {
      _selected = u.topups.isEmpty ? '' : u.topups.first.planId;
    } else {
      final current = u.subscription.isTrial
          ? 'starter'
          : u.subscription.planId;
      _selected = _yearly ? '${current}_annual' : current;
      if (!_options.any((p) => p.planId == _selected)) {
        _selected = _options.isEmpty ? 'starter' : _options.first.planId;
      }
    }
  }

  void _setYearly(bool yearly) {
    if (yearly == _yearly) return;
    Haptics.tap();
    final base = _selected.replaceFirst('_annual', '');
    setState(() {
      _yearly = yearly;
      _error = null;
      _selected = yearly ? '${base}_annual' : base;
      if (!_options.any((p) => p.planId == _selected)) {
        _selected = _options.isEmpty ? _selected : _options.first.planId;
      }
    });
  }

  CheckoutPlan? get _item {
    for (final p in _options) {
      if (p.planId == _selected) return p;
    }
    return null;
  }

  Future<void> _pay() async {
    final item = _item;
    if (item == null || _busy) return;
    final s = context.s;
    setState(() {
      _busy = true;
      _error = null;
    });
    final (outcome, message, upi) = await startCheckout(
      ref,
      planId: item.planId,
    );
    if (!mounted) return;
    if (outcome == CheckoutOutcome.opened || outcome == CheckoutOutcome.paid) {
      Navigator.pop(context, outcome);
      return;
    }
    if (upi != null) {
      setState(() {
        _busy = false;
        _upi = upi;
      });
      return;
    }
    // A snackbar would sit behind this sheet; show the problem in it.
    setState(() {
      _busy = false;
      _byEmail = outcome == CheckoutOutcome.notConfigured;
      _error = switch (outcome) {
        CheckoutOutcome.notConfigured => null,
        CheckoutOutcome.notActive => s.topupNeedsActivePlan,
        _ => message ?? s.paymentPageFailed,
      };
    });
  }

  /// Online payments aren't set up: the owner emails support, who upgrade the plan by hand.
  Future<void> _emailUs() async {
    final item = _item;
    if (item == null) return;
    final s = context.s;
    final business = ref.read(businessProvider).value;
    var ok = false;
    try {
      ok = await ref.read(externalUrlLauncherProvider)(
        upgradeEmailUri(s, item, business),
      );
    } catch (_) {}
    if (!mounted || ok) return;
    setState(() => _error = s.playbookMailFailed(AppEnv.supportEmail));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final item = _item;
    final upi = _upi;
    if (upi != null) return _UpiStep(upi: upi);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.topup ? s.buyMoreMinutes : s.choosePlan,
              style: t.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (widget.topup)
              Text(s.topupValidity, style: t.bodyMedium)
            else
              _CycleToggle(yearly: _yearly, onChanged: _setYearly),
            const SizedBox(height: 16),
            // The business number is the reason to pay: say it up front.
            if (!widget.topup && _options.any((p) => p.businessNumber)) ...[
              const _NumberIncluded(),
              const SizedBox(height: 12),
            ],
            for (final (i, p) in _options.indexed)
              Reveal(
                index: i,
                offset: 8,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OptionCard(
                    item: p,
                    current:
                        !widget.topup &&
                        !widget.usage.subscription.isTrial &&
                        p.basePlanId == widget.usage.subscription.planId &&
                        p.isAnnual == widget.usage.subscription.annual,
                    selected: p.planId == _selected,
                    onTap: () {
                      Haptics.tap();
                      setState(() {
                        _selected = p.planId;
                        _error = null;
                      });
                    },
                  ),
                ),
              ),
            if (item != null) ...[
              const SizedBox(height: 8),
              _Breakdown(item: item),
            ],
            const SizedBox(height: 14),
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.base),
              alignment: Alignment.topCenter,
              child: _error != null
                  ? Padding(
                      key: const ValueKey('checkout-error'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: t.bodyMedium?.copyWith(color: AppColors.hot),
                      ),
                    )
                  : _byEmail
                  ? Padding(
                      key: const ValueKey('checkout-by-email'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(s.upgradeByEmail, style: t.bodyMedium),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (_byEmail)
              PrimaryButton(
                label: s.emailSupport,
                icon: Icons.mail_outline_rounded,
                color: AppColors.brandFill,
                onPressed: item == null ? null : _emailUs,
              )
            else
              PrimaryButton(
                label: s.payAmount(Fmt.inr(item?.totalInr ?? 0)),
                icon: Icons.lock_outline_rounded,
                color: AppColors.brandFill,
                loading: _busy,
                onPressed: item == null || _busy ? null : _pay,
              ),
          ],
        ),
      ),
    );
  }
}

/// Pay [upi] from any UPI app (QR or the app chooser), then report the UTR so
/// support can confirm the payment and start the plan.
class _UpiStep extends ConsumerStatefulWidget {
  const _UpiStep({required this.upi});
  final UpiCheckout upi;
  @override
  ConsumerState<_UpiStep> createState() => _UpiStepState();
}

class _UpiStepState extends ConsumerState<_UpiStep> {
  final _utr = TextEditingController();
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  Future<void> _openUpiApp() async {
    final s = context.s;
    final uri = Uri.tryParse(widget.upi.uri);
    var ok = false;
    try {
      if (uri != null) ok = await ref.read(externalUrlLauncherProvider)(uri);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _error = ok ? null : s.upiAppFailed(widget.upi.vpa));
  }

  Future<void> _copyVpa() async {
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: widget.upi.vpa));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _submit() async {
    final s = context.s;
    final utr = normalizeUtr(_utr.text);
    if (utr == null) {
      setState(() => _error = s.utrInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(usageRepoProvider)
          .submitUpiUtr(orderId: widget.upi.orderId, utr: utr);
      ref.read(dataVersionProvider.notifier).bump();
      Haptics.success();
      if (mounted) Navigator.pop(context, CheckoutOutcome.upiSubmitted);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.code : null;
      setState(() {
        _busy = false;
        _error = switch (code) {
          'invalid_utr' => s.utrInvalid,
          'utr_used' => s.utrUsed,
          'order_closed' || 'not_found' => s.upiOrderClosed,
          _ => friendlyError(e, s),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final upi = widget.upi;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          0,
          AppSpace.page,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.payByUpiTitle(Fmt.inr(upi.amountInr)),
              style: t.headlineSmall,
            ),
            if (upi.payeeName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s.upiPayTo(upi.payeeName), style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // QR codes need dark-on-light to scan, in both themes.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: QrImageView(
                  key: const Key('upi-qr'),
                  data: upi.uri,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              shadow: false,
              child: Row(
                children: [
                  Text(s.upiIdLabel, style: t.bodyMedium),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      upi.vpa,
                      style: t.titleSmall,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    key: const Key('upi-copy-vpa'),
                    tooltip: _copied ? s.copied : s.upiIdLabel,
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 20,
                    ),
                    onPressed: _copyVpa,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.upiNoteHelp(upi.reference),
              style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 14),
            SecondaryButton(
              label: s.payWithUpiApp,
              icon: Icons.account_balance_wallet_outlined,
              onPressed: _busy ? null : _openUpiApp,
            ),
            const SizedBox(height: 20),
            Text(s.utrHelp, style: t.bodyMedium),
            const SizedBox(height: 10),
            TextField(
              key: const Key('upi-utr'),
              controller: _utr,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: InputDecoration(
                labelText: s.utrLabel,
                hintText: '123456789012',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.base),
              alignment: Alignment.topCenter,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      key: const ValueKey('upi-error'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: t.bodyMedium?.copyWith(color: AppColors.hot),
                      ),
                    ),
            ),
            PrimaryButton(
              label: s.submitUtr,
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.brandFill,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleToggle extends StatelessWidget {
  const _CycleToggle({required this.yearly, required this.onChanged});
  final bool yearly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text(s.billingMonthly)),
        ButtonSegment(
          value: true,
          // Two short lines read better than one that wraps mid-phrase.
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.billingYearly, maxLines: 1),
              Text(
                s.oneMonthFree,
                maxLines: 1,
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
      selected: {yearly},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.item,
    required this.selected,
    required this.current,
    required this.onTap,
  });
  final CheckoutPlan item;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final title = item.isTopup
        ? s.topupMinutes(Fmt.number(item.includedMinutes))
        : s.data(item.isAnnual ? _baseName(item) : item.name);
    // One all-in price (GST included); the breakdown below shows the split.
    final sub = item.isTopup
        ? s.inclGst
        : '${s.minutesPerMonth(Fmt.number(item.includedMinutes))} · ${s.inclGst}';
    final price = item.isTopup
        ? Fmt.inr(item.totalInr)
        : (item.isAnnual
              ? s.pricePerYear(Fmt.inr(item.totalInr))
              : s.pricePerMonth(Fmt.inr(item.totalInr)));
    return Semantics(
      selected: selected,
      button: true,
      child: AppCard(
        key: ValueKey('checkout-option-${item.planId}'),
        onTap: onTap,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: Border.all(
          color: selected ? AppColors.ink : AppColors.border,
          width: selected ? 1.6 : 1.2,
        ),
        color: selected ? AppColors.accentSoft : AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 21,
                  color: selected ? AppColors.ink : AppColors.inkFaint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(sub, style: t.bodySmall),
                      if (current) ...[
                        const SizedBox(height: 2),
                        Text(
                          s.currentPlanTag,
                          style: t.labelSmall?.copyWith(color: AppColors.brand),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(price, style: t.titleSmall),
              ],
            ),
            // Under the whole row so it never wraps beside the price.
            if (item.businessNumber)
              Padding(
                padding: const EdgeInsets.only(left: 33, top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.phone_in_talk_rounded,
                      size: 16,
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.planNumberIncluded,
                        key: ValueKey('plan-number-${item.planId}'),
                        style: t.labelLarge?.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// "Starter (annual)" → "Starter" (the toggle already says yearly).
  static String _baseName(CheckoutPlan p) =>
      p.name.replaceFirst(RegExp(r'\s*\(annual\)$'), '');
}

/// "Every plan includes your own business number", above the plans.
class _NumberIncluded extends StatelessWidget {
  const _NumberIncluded();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('plans-include-number'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.phone_in_talk_rounded,
            size: 22,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.plansIncludeNumber,
                  style: t.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.plansIncludeNumberBody,
                  style: t.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.item});
  final CheckoutPlan item;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    Widget row(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k, style: strong ? t.titleSmall : t.bodyMedium)),
          Text(v, style: strong ? t.titleSmall : t.bodyMedium),
        ],
      ),
    );
    return Container(
      key: const ValueKey('checkout-breakdown'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row(s.priceLabel, Fmt.inr(item.priceInr)),
          row(s.gstLabel(gstPercent(item)), Fmt.inr(item.gstInr)),
          row(s.totalToPay, Fmt.inr(item.totalInr), strong: true),
        ],
      ),
    );
  }
}

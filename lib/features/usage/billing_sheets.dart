import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'billing_actions.dart';

/// Plan picker: Starter / Growth, monthly or yearly ("2 months free"), with
/// the GST breakdown. Returns the checkout outcome when the payment page
/// opened or the (mock) payment went through; errors stay inside the sheet.
Future<CheckoutOutcome?> showPlanPickerSheet(BuildContext context, Usage u) =>
    showModalBottomSheet<CheckoutOutcome>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(usage: u, topup: false),
    );

/// "Buy more minutes": top-up packs for an active plan.
Future<CheckoutOutcome?> showTopupSheet(BuildContext context, Usage u) =>
    showModalBottomSheet<CheckoutOutcome>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(usage: u, topup: true),
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
    final (outcome, message) = await startCheckout(ref, planId: item.planId);
    if (!mounted) return;
    if (outcome == CheckoutOutcome.opened || outcome == CheckoutOutcome.paid) {
      Navigator.pop(context, outcome);
      return;
    }
    // A snackbar would sit behind this sheet; show the problem in it.
    setState(() {
      _busy = false;
      _error = switch (outcome) {
        CheckoutOutcome.notConfigured => s.upgradeContact,
        CheckoutOutcome.notActive => s.topupNeedsActivePlan,
        _ => message ?? s.paymentPageFailed,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final item = _item;
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
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      key: const ValueKey('checkout-error'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: t.bodyMedium?.copyWith(color: AppColors.hot),
                      ),
                    ),
            ),
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
          label: Text('${s.billingYearly} · ${s.twoMonthsFree}'),
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
          color: selected ? AppColors.brand : AppColors.border,
          width: selected ? 1.6 : 1.2,
        ),
        color: selected ? AppColors.brandSoft : AppColors.surface,
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 21,
              color: selected ? AppColors.brand : AppColors.inkFaint,
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
      ),
    );
  }

  /// "Starter (annual)" → "Starter" (the toggle already says yearly).
  static String _baseName(CheckoutPlan p) =>
      p.name.replaceFirst(RegExp(r'\s*\(annual\)$'), '');
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

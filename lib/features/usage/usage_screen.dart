import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'billing_actions.dart';

/// Label for a plan's billing status.
String planStatusLabel(S s, PlanStatus status) => switch (status) {
  PlanStatus.trial => s.planTrial,
  PlanStatus.active => s.planActive,
  PlanStatus.pastDue => s.planPaymentDue,
  PlanStatus.cancelled => s.planCancelled,
};

class UsageScreen extends ConsumerStatefulWidget {
  const UsageScreen({super.key});

  @override
  ConsumerState<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends ConsumerState<UsageScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

  /// Set while the payment page is open outside the app.
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      // The webhook may land a moment after the user returns: refresh now
      // and once more shortly after.
      ref.read(dataVersionProvider.notifier).bump();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) ref.read(dataVersionProvider.notifier).bump();
      });
    }
  }

  Future<void> _checkout(Usage u) async {
    if (_busy) return;
    setState(() => _busy = true);
    final (outcome, message) = await startCheckout(
      ref,
      planId: u.checkoutPlan.planId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final s = context.s;
    final text = switch (outcome) {
      CheckoutOutcome.opened => null,
      CheckoutOutcome.paid => s.paymentReceived,
      CheckoutOutcome.notConfigured => s.upgradeContact,
      CheckoutOutcome.failed => message ?? s.paymentPageFailed,
    };
    if (outcome == CheckoutOutcome.opened) _awaitingReturn = true;
    if (text != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final usage = ref.watch(usageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.planAndUsage)),
      body: AsyncView<Usage>(
        value: usage,
        onRetry: () => ref.invalidate(usageProvider),
        data: (u) {
          final periodEnd = u.subscription.currentPeriodEnd;
          final paidPlan = !u.subscription.isTrial;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              0,
              AppSpace.page,
              32,
            ),
            children: [
              Reveal(
                child: AppCard(
                  color: AppColors.strong,
                  border: Border.all(color: Colors.transparent),
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.data(u.subscription.planName),
                              style: t.labelLarge?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StatusChip(status: u.subscription.status),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AnimatedCount(
                        value: u.minutesRemaining,
                        countUp: true,
                        format: Fmt.number,
                        style: t.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w500,
                          height: 1,
                          letterSpacing: -1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.minutesRemaining,
                        style: t.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 22),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: u.ratio),
                        duration: AppMotion.of(
                          context,
                          const Duration(milliseconds: 1100),
                        ),
                        curve: AppMotion.emphasized,
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: Colors.white24,
                          color: u.ratio > 0.85
                              ? const Color(0xFFFF7A7F)
                              : AppColors.liveDot,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.nUsed(Fmt.number(u.minutesUsed)),
                              style: t.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          Text(
                            s.ofTotal(
                              Fmt.number(u.subscription.includedMinutes),
                            ),
                            style: t.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Reveal(
                index: 1,
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      _Kv(
                        s.callsMade,
                        Fmt.number(u.callsMade),
                        last: !paidPlan,
                      ),
                      if (periodEnd != null)
                        _Kv(
                          u.subscription.status.blocksCalling
                              ? s.paymentDueOn
                              : s.renewsOn,
                          s.date(periodEnd.toLocal()),
                        ),
                      if (paidPlan)
                        _Kv(
                          s.extraMinutes,
                          s.perMin(Fmt.inr(u.ratePerMinuteInr)),
                          last: true,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Reveal(
                index: 2,
                child: PrimaryButton(
                  label: u.subscription.isTrial ? s.upgrade : s.renewPlan,
                  icon: Icons.workspace_premium_outlined,
                  color: AppColors.brandFill,
                  loading: _busy,
                  onPressed: _busy ? null : () => _checkout(u),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.planOffer(
                  s.data(u.checkoutPlan.name),
                  Fmt.inr(u.checkoutPlan.priceInr),
                  Fmt.number(u.checkoutPlan.includedMinutes),
                ),
                style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                u.subscription.isTrial
                    ? s.trialMinutesNote
                    : s.onlyConnectedCount,
                style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final alert = status.blocksCalling;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFFF7A7F) : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        planStatusLabel(context.s, status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.last = false});
  final String k;
  final String v;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(k, style: t.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              v,
              style: t.titleSmall,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

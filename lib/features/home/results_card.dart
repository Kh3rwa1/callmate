import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../agent/owner_test_call_sheet.dart';

/// Home "This week" section: what the AI achieved vs last week and what it
/// is worth. Before the AI has called anyone, it offers a test call to the
/// owner's own phone instead.
class HomeResultsSection extends ConsumerWidget {
  const HomeResultsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final results = ref.watch(weekResultsProvider).value;
    // Quiet while loading or on error: Home already has its own error state.
    if (results == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(s.resultsThisWeek),
        results.hasCalls
            ? ResultsCard(results: results)
            : const HearYourAiCard(),
      ],
    );
  }
}

/// This week's numbers with the change vs last week, plus the estimate.
class ResultsCard extends StatelessWidget {
  const ResultsCard({super.key, required this.results});
  final ResultsSummary results;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final c = results.current;
    final p = results.previous;
    final worth = c.estimatedValueInr;
    final avg = results.avgDealValueInr;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _Metric(
                  value: c.enquiries,
                  previous: p.enquiries,
                  label: s.statEnquiries,
                  onTap: () => context.go('/leads?filter=new'),
                ),
                _Metric(
                  value: c.callsConnected,
                  previous: p.callsConnected,
                  label: s.statConnected,
                  onTap: () => context.go('/calls?filter=connected'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _Metric(
                  value: c.readyToBuy,
                  previous: p.readyToBuy,
                  label: s.statHot,
                  accent: AppColors.hot,
                  onTap: () => context.go('/leads?filter=hot'),
                ),
                _Metric(
                  value: c.followUpsSent,
                  previous: p.followUpsSent,
                  label: s.statMessagesSent,
                  onTap: () => context.go('/followups'),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          Semantics(
            button: true,
            child: InkWell(
              onTap: () {
                Haptics.tap();
                showAvgSaleSheet(context);
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.card),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.currency_rupee_rounded,
                      size: 20,
                      color: worth == null
                          ? AppColors.inkFaint
                          : AppColors.success,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: worth == null || avg == null
                          ? Text(
                              s.addAvgSaleCta,
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.resultsWorth(Fmt.inr(worth)),
                                  style: t.titleSmall,
                                ),
                                Text(
                                  s.resultsWorthDetail(
                                    c.readyToBuy,
                                    Fmt.inr(avg),
                                  ),
                                  style: t.bodySmall?.copyWith(
                                    color: AppColors.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.previous,
    required this.label,
    required this.onTap,
    this.accent,
  });
  final int value;
  final int previous;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final delta = value - previous;
    return Expanded(
      child: Semantics(
        button: true,
        label: '$value $label, ${s.deltaVsLastWeek(delta)}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.cardSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedCount(
                  value: value,
                  countUp: true,
                  format: Fmt.number,
                  style: t.headlineSmall?.copyWith(
                    color: accent ?? AppColors.ink,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.8,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(
                    color: AppColors.inkFaint,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                if (delta != 0)
                  Text(
                    s.deltaVsLastWeek(delta),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(
                      color: delta > 0 ? AppColors.success : AppColors.inkFaint,
                      letterSpacing: 0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-run nudge: let the AI call the owner's own phone.
class HearYourAiCard extends ConsumerWidget {
  const HearYourAiCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ring_volume_rounded, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(child: Text(s.hearYourAiTitle, style: t.titleMedium)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.hearYourAiBody(name),
            style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: s.callMeNow,
            icon: Icons.call_rounded,
            onPressed: () => showOwnerTestCallSheet(context),
          ),
        ],
      ),
    );
  }
}

/// Sets (or removes) the business's average sale value.
Future<void> showAvgSaleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _AvgSaleSheet(),
  );
}

class _AvgSaleSheet extends ConsumerStatefulWidget {
  const _AvgSaleSheet();
  @override
  ConsumerState<_AvgSaleSheet> createState() => _AvgSaleSheetState();
}

class _AvgSaleSheetState extends ConsumerState<_AvgSaleSheet> {
  late final TextEditingController _amount;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(businessProvider).value?.avgDealValueInr;
    _amount = TextEditingController(text: current?.toString() ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final s = context.s;
    final value = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (!remove && (value == null || value < 1 || value > 100000000)) {
      setState(() => _error = s.avgSaleInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(businessRepoProvider);
      final biz = await repo.getBusiness();
      if (biz == null) throw StateError('No business');
      await repo.saveBusiness(
        remove
            ? biz.copyWith(clearAvgDealValue: true)
            : biz.copyWith(avgDealValueInr: value),
      );
      Haptics.success();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      // A snackbar would sit behind this sheet; show the error in it.
      setState(() {
        _busy = false;
        _error = friendlyError(e, s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final hasValue = ref.watch(businessProvider).value?.avgDealValueInr != null;
    return SafeArea(
      child: Padding(
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
            Text(s.avgSaleTitle, style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              s.avgSaleHint,
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: s.avgSaleTitle,
                prefixText: '₹ ',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: s.save, loading: _busy, onPressed: _save),
            if (hasValue) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _save(remove: true),
                  child: Text(s.removeValue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

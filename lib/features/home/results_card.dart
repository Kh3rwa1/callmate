import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../l10n/l10n.dart';
import '../agent/owner_test_call_sheet.dart';

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

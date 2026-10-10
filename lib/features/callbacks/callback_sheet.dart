import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Quick callback scheduler with smart presets (AI suggestion first).
Future<Callback?> showCallbackSheet(
  BuildContext context,
  WidgetRef ref, {
  required Lead lead,
  DateTime? suggested,
}) {
  return showModalBottomSheet<Callback>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) =>
        _CallbackSheet(lead: lead, suggested: suggested ?? lead.callbackAt),
  );
}

class _CallbackSheet extends ConsumerStatefulWidget {
  const _CallbackSheet({required this.lead, this.suggested});
  final Lead lead;
  final DateTime? suggested;
  @override
  ConsumerState<_CallbackSheet> createState() => _CallbackSheetState();
}

class _CallbackSheetState extends ConsumerState<_CallbackSheet> {
  late DateTime _at;
  bool _busy = false;
  String? _error;
  late final List<(String, DateTime, bool)> _presets;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _at = widget.suggested != null && widget.suggested!.isAfter(n)
        ? widget.suggested!
        : DateTime(n.year, n.month, n.day + 1, 11);
  }

  /// Presets need the UI language, so they're built on first build.
  void _seed(S s) {
    if (_seeded) return;
    _seeded = true;
    final n = DateTime.now();
    final tomorrow = DateTime(n.year, n.month, n.day + 1);
    final suggested = widget.suggested != null && widget.suggested!.isAfter(n)
        ? widget.suggested
        : null;
    _presets = [
      if (suggested != null)
        (s.suggestedBy(ref.read(employeeNameProvider)), suggested, true),
      // Fixed slots, minus the one that equals the suggestion.
      for (final p in [
        if (n.hour < 17)
          (s.todaySixPm, DateTime(n.year, n.month, n.day, 18), false),
        (s.tomorrowElevenAm, tomorrow.add(const Duration(hours: 11)), false),
        (s.tomorrowSixPm, tomorrow.add(const Duration(hours: 18)), false),
      ])
        if (p.$2 != suggested) p,
    ];
    _at = _presets.first.$2;
  }

  Future<void> _custom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (tm == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  Future<void> _save() async {
    final s = context.s;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cb = await ref
          .read(callbackRepoProvider)
          .schedule(leadId: widget.lead.id, at: _at);
      Haptics.success();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, cb);
      messenger.showSnackBar(
        SnackBar(content: Text(s.callbackSetFor(s.friendlyFuture(_at)))),
      );
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
    _seed(s);
    final t = Theme.of(context).textTheme;
    final custom = !_presets.any((p) => p.$2 == _at);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.scheduleCallbackTitle, style: t.headlineSmall),
            const SizedBox(height: 2),
            Text(widget.lead.name, style: t.bodyMedium),
            const SizedBox(height: 18),
            for (final (i, (label, at, highlight)) in _presets.indexed)
              Reveal(
                index: i,
                offset: 8,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Option(
                    label: label,
                    sub: highlight ? s.friendlyFuture(at) : null,
                    selected: _at == at,
                    highlight: highlight,
                    onTap: () {
                      Haptics.tap();
                      setState(() => _at = at);
                    },
                  ),
                ),
              ),
            Reveal(
              index: _presets.length,
              offset: 8,
              child: _Option(
                label: s.pickDateTime,
                sub: custom ? s.friendlyFuture(_at) : s.chooseAnySlot,
                selected: custom,
                onTap: _custom,
                icon: Icons.edit_calendar_outlined,
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.base),
              alignment: Alignment.topCenter,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: t.bodyMedium?.copyWith(color: AppColors.hot),
                      ),
                    ),
            ),
            PrimaryButton(
              label: s.scheduleCallback,
              icon: Icons.event_available_rounded,
              loading: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    this.sub,
    required this.selected,
    required this.onTap,
    this.highlight = false,
    this.icon,
  });
  final String label;
  final String? sub;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: AppCard(
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
              icon ??
                  (highlight
                      ? Icons.auto_awesome_rounded
                      : Icons.schedule_outlined),
              size: 21,
              color: selected
                  ? AppColors.brand
                  : (highlight ? AppColors.brand : AppColors.inkFaint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t.titleSmall),
                  if (sub != null) Text(sub!, style: t.bodySmall),
                ],
              ),
            ),
            PopSwitcher(
              child: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey('on'),
                      color: AppColors.brand,
                      size: 22,
                    )
                  : const SizedBox(key: ValueKey('off'), width: 22),
            ),
          ],
        ),
      ),
    );
  }
}

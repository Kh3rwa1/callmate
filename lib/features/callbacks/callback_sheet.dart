import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

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
  late final List<(String, DateTime)> _presets;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final tomorrow = DateTime(n.year, n.month, n.day + 1);
    final suggested = widget.suggested != null && widget.suggested!.isAfter(n)
        ? widget.suggested
        : null;
    _presets = [
      if (suggested != null)
        ('Suggested by ${ref.read(employeeNameProvider)}', suggested),
      // Fixed slots, minus the one that equals the suggestion.
      for (final p in [
        if (n.hour < 17) ('Today, 6 PM', DateTime(n.year, n.month, n.day, 18)),
        ('Tomorrow, 11 AM', tomorrow.add(const Duration(hours: 11))),
        ('Tomorrow, 6 PM', tomorrow.add(const Duration(hours: 18))),
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cb = await ref
          .read(callbackRepoProvider)
          .schedule(leadId: widget.lead.id, at: _at);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pop(context, cb);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Callback set for ${Fmt.friendlyFuture(_at)}')),
      );
    } catch (e) {
      if (!mounted) return;
      // A snackbar would sit behind this sheet; show the error in it.
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schedule callback', style: t.headlineSmall),
            const SizedBox(height: 2),
            Text(widget.lead.name, style: t.bodyMedium),
            const SizedBox(height: 18),
            for (final (label, at) in _presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Option(
                  label: label,
                  sub: label.startsWith('Suggested')
                      ? Fmt.friendlyFuture(at)
                      : null,
                  selected: _at == at,
                  highlight: label.startsWith('Suggested'),
                  onTap: () => setState(() => _at = at),
                ),
              ),
            _Option(
              label: 'Pick date & time',
              sub: _presets.any((p) => p.$2 == _at)
                  ? 'Choose any slot'
                  : Fmt.friendlyFuture(_at),
              selected: !_presets.any((p) => p.$2 == _at),
              onTap: _custom,
              icon: Icons.edit_calendar_outlined,
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(
                _error!,
                style: t.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 10),
            ],
            PrimaryButton(
              label: 'Schedule Callback',
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
          color: selected ? AppColors.ink : AppColors.border,
          width: selected ? 1.6 : 1.2,
        ),
        color: Colors.white,
        child: Row(
          children: [
            Icon(
              icon ??
                  (highlight
                      ? Icons.auto_awesome_rounded
                      : Icons.schedule_outlined),
              size: 21,
              color: selected ? AppColors.ink : AppColors.inkFaint,
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
            if (selected)
              const Icon(Icons.check_rounded, color: AppColors.ink, size: 20),
          ],
        ),
      ),
    );
  }
}

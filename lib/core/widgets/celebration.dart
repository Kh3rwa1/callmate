import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'mascot.dart';

/// Remembers which "ready to buy" moments were already celebrated, so each
/// lead gets one celebration even when several events report it (call
/// finished, push notification, a refresh…).
class CelebrationLedger {
  final _seen = <String>{};

  /// True the first time any of [keys] is seen; marks them all as seen.
  bool claim(Iterable<String> keys) {
    final fresh = keys.every((k) => !_seen.contains(k));
    _seen.addAll(keys);
    return fresh;
  }
}

final celebrationLedgerProvider = Provider<CelebrationLedger>(
  (_) => CelebrationLedger(),
);

/// What to celebrate for a backend event, or null.
@visibleForTesting
({List<String> keys, String? name})? hotMomentFor(BackendEvent e) {
  if (e is CallCompletedEvent) {
    final c = e.call;
    if (c.leadScore?.temperature != LeadTemperature.hot) return null;
    return (
      keys: [
        'lead:${c.leadId}',
        '/calls/${c.id}/result',
        if (c.followUpId != null) '/followups/${c.followUpId}',
        if (e.followUp != null) '/followups/${e.followUp!.id}',
      ],
      name: c.leadName,
    );
  }
  if (e is NotificationEvent &&
      e.notification.type == NotificationType.hotLead) {
    final route = e.notification.route;
    final lead = RegExp(r'^/leads/([^/?]+)').firstMatch(route)?.group(1);
    return (
      keys: [lead != null ? 'lead:$lead' : route, 'n:${e.notification.id}'],
      name: null,
    );
  }
  return null;
}

/// Wraps the signed-in app: when a lead becomes "ready to buy" while the
/// app is open, the mascot pops in celebrating with a small confetti burst
/// and a medium haptic – once per lead, gone within 1.2 s. Under reduced
/// motion it is a still card (no confetti, no movement).
class HotLeadCelebrator extends ConsumerStatefulWidget {
  const HotLeadCelebrator({super.key, required this.child});
  final Widget child;

  static const showFor = Duration(milliseconds: 1200);

  @override
  ConsumerState<HotLeadCelebrator> createState() => _HotLeadCelebratorState();
}

class _HotLeadCelebratorState extends ConsumerState<HotLeadCelebrator> {
  StreamSubscription<BackendEvent>? _sub;
  Timer? _hide;
  ({String? name, int id})? _current;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(backendEventsProvider).stream.listen(_onEvent);
  }

  void _onEvent(BackendEvent e) {
    final m = hotMomentFor(e);
    if (m == null || !mounted) return;
    if (!ref.read(celebrationLedgerProvider).claim(m.keys)) return;
    HapticFeedback.mediumImpact();
    _hide?.cancel();
    setState(() => _current = (name: m.name, id: ++_count));
    _hide = Timer(HotLeadCelebrator.showFor, () {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _current;
    return Stack(
      children: [
        widget.child,
        if (c != null)
          Positioned(
            left: AppSpace.page,
            right: AppSpace.page,
            top: MediaQuery.paddingOf(context).top + AppSpace.md,
            child: IgnorePointer(
              child: CelebrationToast(key: ValueKey(c.id), name: c.name),
            ),
          ),
      ],
    );
  }
}

/// The card that pops in: mascot celebrating, confetti, one line.
class CelebrationToast extends StatelessWidget {
  const CelebrationToast({super.key, this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final reduced = AppMotion.reduced(context);
    final first = name?.trim().split(' ').first;
    final text = first == null || first.isEmpty
        ? s.celebrateReadyAny
        : s.celebrateReady(first);
    final card = Container(
      key: const Key('celebration'),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.strong,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.raised,
      ),
      child: Row(
        children: [
          Mascot(
            state: MascotState.celebrating,
            size: 64,
            haloColor: Colors.white.withValues(alpha: 0.09),
            semanticLabel: '',
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: t.titleMedium?.copyWith(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
    if (reduced) return card;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        const Positioned(
          left: -40,
          top: -90,
          child: ConfettiBurst(
            size: 240,
            count: 22,
            duration: Duration(milliseconds: 1100),
            colors: [
              Color(0xFFF5A524),
              Color(0xFF1F5BFF),
              Color(0xFFFD8BB2),
              Color(0xFF80BDFC),
            ],
          ),
        ),
        PopIn(child: card),
      ],
    );
  }
}

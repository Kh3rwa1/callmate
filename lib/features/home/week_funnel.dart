import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'results_card.dart';

/// Bar widths for a funnel, as fractions of the widest stage (0..1).
///
/// Non-zero stages get at least [minVisible] so a single lead still shows a
/// sliver of colour; zero stays empty. All zeros → all zero.
List<double> funnelFractions(List<int> counts, {double minVisible = 0.04}) {
  final top = counts.fold<int>(0, math.max);
  if (top <= 0) return List.filled(counts.length, 0);
  return [
    for (final c in counts)
      c <= 0 ? 0.0 : math.max(minVisible, math.min(1.0, c / top)),
  ];
}

/// Calls per local day for the 7 days ending today (oldest first).
List<int> callsPerDay(Iterable<DateTime> starts, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final out = List.filled(7, 0);
  for (final s in starts) {
    final l = s.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    final ago = today.difference(day).inDays;
    if (ago >= 0 && ago < 7) out[6 - ago]++;
  }
  return out;
}

/// Calls in each of the last 7 days, from the calls list (up to 5 pages of
/// 100, newest first – enough for any small business's week).
final weekCallsProvider = FutureProvider<List<int>>((ref) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(callRepoProvider);
  final now = ref.watch(clockProvider)();
  final since = DateTime(now.year, now.month, now.day - 6);
  final starts = <DateTime>[];
  String? cursor;
  for (var page = 0; page < 5; page++) {
    final p = await repo.list(cursor: cursor, limit: 100);
    starts.addAll(p.items.map((c) => c.startedAt));
    final oldest = p.items.isEmpty ? null : p.items.last.startedAt.toLocal();
    if (!p.hasMore || oldest == null || oldest.isBefore(since)) break;
    cursor = p.nextCursor;
  }
  return callsPerDay(starts, now);
});

/// Home "This week": the money it could be worth (when the owner set an
/// average sale), a four-step funnel and a 7-day call sparkline.
class WeekFunnelSection extends ConsumerWidget {
  const WeekFunnelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final results = ref.watch(weekResultsProvider).value;
    // Quiet while loading or on error: Home already has its own error state.
    if (results == null || !results.hasCalls) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          s.resultsThisWeek,
          trailing: Text(
            s.vsLastWeek,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
          ),
        ),
        WeekFunnelCard(
          results: results,
          daily: ref.watch(weekCallsProvider).value,
        ),
      ],
    );
  }
}

class WeekFunnelCard extends StatelessWidget {
  const WeekFunnelCard({super.key, required this.results, this.daily});
  final ResultsSummary results;

  /// Calls per day, oldest first (7 values); null while loading.
  final List<int>? daily;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final c = results.current;
    final p = results.previous;
    final worth = c.estimatedValueInr;
    final counts = [c.enquiries, c.callsConnected, c.interested, c.readyToBuy];
    final prev = [p.enquiries, p.callsConnected, p.interested, p.readyToBuy];
    final widths = funnelFractions(counts);
    final stages = [
      (s.statEnquiries, AppColors.brand.withValues(alpha: 0.35), '/leads'),
      (s.funnelTalked, AppColors.brand, '/calls?filter=connected'),
      (s.statInterested, AppColors.warm, '/leads?filter=warm'),
      (s.statHot, AppColors.hot, '/leads?filter=hot'),
    ];
    return AppCard(
      key: const Key('week-funnel'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Money first: the biggest number on the card.
          Semantics(
            button: true,
            child: InkWell(
              onTap: () {
                Haptics.tap();
                showAvgSaleSheet(context);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.lg,
                  AppSpace.md,
                  AppSpace.md,
                ),
                child: worth == null
                    ? Row(
                        children: [
                          Icon(
                            Icons.currency_rupee_rounded,
                            size: 20,
                            color: AppColors.accentInk,
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Text(
                              s.addAvgSaleCta,
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.inkFaint,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedCount(
                            key: const Key('funnel-worth'),
                            value: worth,
                            countUp: true,
                            format: (n) => Fmt.inr(n),
                            style: t.displayLarge?.copyWith(
                              color: AppColors.accentInk,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            s.worthCaption(c.readyToBuy),
                            style: t.bodyMedium,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Column(
              children: [
                for (var i = 0; i < stages.length; i++)
                  _FunnelRow(
                    key: Key('funnel-$i'),
                    label: stages[i].$1,
                    color: stages[i].$2,
                    value: counts[i],
                    delta: counts[i] - prev[i],
                    fraction: widths[i],
                    hot: i == 3,
                    onTap: () => context.go(stages[i].$3),
                  ),
              ],
            ),
          ),
          if (daily != null) ...[
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.lg,
              ),
              child: Semantics(
                label: s.weekCallsSemantics(daily!.fold(0, (a, b) => a + b)),
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s.weekCallsLabel, style: t.bodyMedium),
                    ),
                    const SizedBox(width: AppSpace.md),
                    SizedBox(
                      width: 112,
                      height: 32,
                      child: CustomPaint(
                        key: const Key('sparkline'),
                        painter: SparklinePainter(
                          values: daily!,
                          color: AppColors.brand,
                          fill: AppColors.brand.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({
    super.key,
    required this.label,
    required this.color,
    required this.value,
    required this.delta,
    required this.fraction,
    required this.onTap,
    this.hot = false,
  });
  final String label;
  final Color color;
  final int value;
  final int delta;
  final double fraction;
  final VoidCallback onTap;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$value $label, ${s.deltaVsLastWeek(delta)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    AnimatedCount(
                      value: value,
                      countUp: true,
                      format: Fmt.number,
                      style: t.headlineSmall?.copyWith(
                        color: hot && value > 0 ? AppColors.hot : AppColors.ink,
                        height: 1.1,
                      ),
                    ),
                    if (delta != 0) ...[
                      const SizedBox(width: AppSpace.sm),
                      DeltaChip(delta: delta),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (_, c) => Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: fraction),
                        duration: AppMotion.of(
                          context,
                          const Duration(milliseconds: 700),
                        ),
                        curve: AppMotion.emphasized,
                        builder: (_, f, _) => Container(
                          height: 8,
                          width: c.maxWidth * f,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ],
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

/// "▲ 3" / "▼ 2" in a neutral chip. Change vs last week is information,
/// not good/bad news, so it never borrows the hot red or success green.
class DeltaChip extends StatelessWidget {
  const DeltaChip({super.key, required this.delta});
  final int delta;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.coldSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      '${delta > 0 ? '▲' : '▼'} ${Fmt.number(delta.abs())}',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.inkSoft,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// A tiny 7-point line chart with a soft fill and a dot on today.
class SparklinePainter extends CustomPainter {
  SparklinePainter({required this.values, required this.color, this.fill});
  final List<int> values;
  final Color color;
  final Color? fill;

  /// Points in [size] space (exposed for tests).
  static List<Offset> points(List<int> values, Size size) {
    if (values.isEmpty) return const [];
    final top = math.max(1, values.fold<int>(0, math.max));
    const pad = 3.0;
    final h = size.height - pad * 2;
    final step = values.length == 1
        ? 0.0
        : (size.width - pad * 2) / (values.length - 1);
    return [
      for (var i = 0; i < values.length; i++)
        Offset(pad + step * i, pad + h - h * values[i] / top),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = points(values, size);
    if (pts.length < 2) return;
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    if (fill != null) {
      final area = Path.from(line)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = fill!);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pts.last, 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.color != color || old.fill != fill || !_same(old.values, values);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

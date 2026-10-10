import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';
import '../leads/leads_controller.dart';

final callFilterProvider = NotifierProvider<CallFilterController, CallFilter>(
  CallFilterController.new,
);

class CallFilterController extends Notifier<CallFilter> {
  @override
  CallFilter build() => CallFilter.all;
  void set(CallFilter f) => state = f;
}

final callsListProvider = NotifierProvider<CallsList, PagedState<Call>>(
  CallsList.new,
);

class CallsList extends Notifier<PagedState<Call>> {
  int _gen = 0;
  @override
  PagedState<Call> build() {
    ref.watch(callFilterProvider);
    ref.listen(dataVersionProvider, (_, _) => refresh(silent: true));
    Future.microtask(refresh);
    return const PagedState(loading: true);
  }

  Future<void> refresh({bool silent = false}) async {
    final gen = ++_gen;
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final keep = silent ? state.items.length.clamp(20, 200) : 20;
      final p = await ref
          .read(callRepoProvider)
          .list(filter: ref.read(callFilterProvider), limit: keep);
      if (gen != _gen) return;
      state = PagedState(
        items: p.items,
        hasMore: p.hasMore,
        cursor: p.nextCursor,
      );
    } catch (e) {
      if (gen == _gen) state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    final gen = _gen;
    state = state.copyWith(loadingMore: true);
    try {
      final p = await ref
          .read(callRepoProvider)
          .list(filter: ref.read(callFilterProvider), cursor: state.cursor);
      if (gen != _gen) return;
      state = state.copyWith(
        items: [...state.items, ...p.items],
        hasMore: p.hasMore,
        cursor: p.nextCursor,
        loadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false);
    }
  }
}

/// Calls – "What did my AI employee do?"  (an activity log, not a dialer)
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key, this.initialFilter});
  final String? initialFilter;
  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _apply();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(callsListProvider.notifier).loadMore();
      }
    });
  }

  void _apply() {
    final f = switch (widget.initialFilter) {
      'connected' => CallFilter.connected,
      'no_answer' => CallFilter.noAnswer,
      'hot' => CallFilter.hot,
      'all' => CallFilter.all,
      _ => null,
    };
    if (f != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(callFilterProvider.notifier).set(f),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CallsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialFilter != widget.initialFilter) _apply();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final f = ref.watch(callFilterProvider);
    final st = ref.watch(callsListProvider);
    final agent = ref.watch(agentProvider).value;
    final filters = [
      (CallFilter.all, s.filterAll, null),
      (CallFilter.connected, s.filterConnected, null),
      (CallFilter.noAnswer, s.filterNoAnswer, null),
      (CallFilter.hot, s.filterHot, Icons.local_fire_department_rounded),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                12,
                AppSpace.page,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(s.aiCallsTitle, style: t.headlineMedium),
                    ),
                  ),
                  const MascotAvatar(size: 40, state: MascotState.calling),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FilterChipRow(
              children: [
                for (final (v, label, icon) in filters)
                  AppFilterChip(
                    label: label,
                    selected: f == v,
                    icon: icon,
                    iconColor: AppColors.hot,
                    onSelected: () =>
                        ref.read(callFilterProvider.notifier).set(v),
                  ),
              ],
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.base),
                switchInCurve: AppMotion.standard,
                child: _list(context, st, f, s.employeeName(agent?.name)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    PagedState<Call> st,
    CallFilter f,
    String agentName,
  ) {
    final s = context.s;
    if (st.loading && st.items.isEmpty) {
      return const SkeletonList(
        key: ValueKey('loading'),
        padding: EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 20),
      );
    }
    if (st.error != null && st.items.isEmpty) {
      return ErrorState(
        key: const ValueKey('error'),
        message: friendlyError(st.error!, s),
        onRetry: () => ref.read(callsListProvider.notifier).refresh(),
      );
    }
    if (st.items.isEmpty) {
      return EmptyState(
        key: ValueKey('empty-$f'),
        title: s.noCallsYetBy(agentName),
        message: s.startCampaignToSeeCalls,
        mascot: MascotState.calling,
        actionLabel: s.callNewLeadsCount(0),
        onAction: () => context.push('/campaign/new'),
      );
    }
    // Group by day: a heading, then one grouped card of slim rows.
    final rows = <Object>[];
    DateTime? lastDay;
    for (final c in st.items) {
      final d = DateTime(c.startedAt.year, c.startedAt.month, c.startedAt.day);
      if (d != lastDay) {
        rows.add(d);
        lastDay = d;
      }
      rows.add(c);
    }
    return RefreshIndicator(
      key: const ValueKey('list'),
      color: AppColors.brand,
      backgroundColor: AppColors.surface,
      onRefresh: () =>
          ref.read(callsListProvider.notifier).refresh(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 28),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return st.hasMore
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : const SizedBox(height: 8);
          }
          final r = rows[i];
          if (r is DateTime) {
            return SectionLabel(
              s.dayLabel(r),
              padding: EdgeInsets.fromLTRB(2, i == 0 ? 8 : 28, 2, 10),
            );
          }
          final call = r as Call;
          final first = rows[i - 1] is DateTime;
          final last = i + 1 >= rows.length || rows[i + 1] is DateTime;
          return Reveal(
            key: ValueKey(call.id),
            id: 'call-${f.name}-${call.id}',
            index: i < 12 ? i : 0,
            child: CallCard(call: call, first: first, last: last),
          );
        },
      ),
    );
  }
}

/// One slim row inside a day's grouped card.
class CallCard extends StatelessWidget {
  const CallCard({
    super.key,
    required this.call,
    this.first = true,
    this.last = true,
  });
  final Call call;

  /// Position inside the grouped card (controls corners and divider).
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final c = call;
    final connected = c.status.isConnected;
    const r = Radius.circular(AppRadius.card);
    final radius = BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
    final meta = connected
        ? s.connectedFor(_shortDuration(c.duration))
        : s.callStatus(c.status);
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label:
            '${Fmt.time(c.startedAt)}, ${c.leadName}, ${s.callStatus(c.status)}',
        child: Material(
          color: AppColors.surface,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(
              connected ? '/calls/${c.id}/result' : '/calls/${c.id}',
            ),
            child: Column(
              children: [
                if (!first) const Divider(height: 1, thickness: 1, indent: 70),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        connected
                            ? LeadAvatar(
                                name: c.leadName,
                                temperature:
                                    c.leadScore?.temperature ??
                                    LeadTemperature.unknown,
                                size: 40,
                              )
                            : Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.phone_missed_outlined,
                                  size: 19,
                                  color: AppColors.inkFaint,
                                ),
                              ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.leadName,
                                      style: t.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    Fmt.time(c.startedAt),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: t.bodySmall?.copyWith(
                                      color: AppColors.inkFaint,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall?.copyWith(
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                  ),
                                  if (c.leadScore != null) ...[
                                    const SizedBox(width: 8),
                                    ScoreBadge(score: c.leadScore),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

/// "01:37" → "1:37".
String _shortDuration(Duration d) {
  final s = Fmt.duration(d);
  return s.startsWith('0') && s.length > 4 ? s.substring(1) : s;
}

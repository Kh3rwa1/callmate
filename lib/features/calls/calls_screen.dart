import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../leads/leads_controller.dart';

final callFilterProvider = NotifierProvider<CallFilterController, CallFilter>(CallFilterController.new);

class CallFilterController extends Notifier<CallFilter> {
  @override
  CallFilter build() => CallFilter.all;
  void set(CallFilter f) => state = f;
}

final callsListProvider = NotifierProvider<CallsList, PagedState<Call>>(CallsList.new);

class CallsList extends Notifier<PagedState<Call>> {
  int _gen = 0;
  @override
  PagedState<Call> build() {
    ref.watch(callFilterProvider);
    ref.listen(dataVersionProvider, (_, __) => refresh(silent: true));
    Future.microtask(refresh);
    return const PagedState(loading: true);
  }

  Future<void> refresh({bool silent = false}) async {
    final gen = ++_gen;
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final keep = silent ? state.items.length.clamp(20, 200) : 20;
      final p = await ref.read(callRepoProvider).list(filter: ref.read(callFilterProvider), limit: keep);
      if (gen != _gen) return;
      state = PagedState(items: p.items, hasMore: p.hasMore, cursor: p.nextCursor);
    } catch (e) {
      if (gen == _gen) state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    final gen = _gen;
    state = state.copyWith(loadingMore: true);
    try {
      final p = await ref.read(callRepoProvider).list(filter: ref.read(callFilterProvider), cursor: state.cursor);
      if (gen != _gen) return;
      state = state.copyWith(items: [...state.items, ...p.items], hasMore: p.hasMore, cursor: p.nextCursor, loadingMore: false);
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
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) ref.read(callsListProvider.notifier).loadMore();
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
    if (f != null) WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(callFilterProvider.notifier).set(f));
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
    final t = Theme.of(context).textTheme;
    final f = ref.watch(callFilterProvider);
    final s = ref.watch(callsListProvider);
    final agent = ref.watch(agentProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text('Calls', style: t.headlineMedium)),
                        Text('Everything ${agent?.name ?? 'Riya'} did for you', style: t.bodyMedium),
                      ],
                    ),
                  ),
                  const MascotAvatar(size: 46, state: MascotState.calling),
                ],
              ),
            ),
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.page, vertical: 12),
                children: [
                  for (final (v, label) in const [
                    (CallFilter.all, 'All'),
                    (CallFilter.connected, 'Connected'),
                    (CallFilter.noAnswer, 'No Answer'),
                    (CallFilter.hot, '🔥 Hot'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: f == v,
                        labelStyle: TextStyle(fontWeight: FontWeight.w700, color: f == v ? Colors.white : AppColors.inkSoft),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          ref.read(callFilterProvider.notifier).set(v);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _list(s, agent?.name ?? 'Riya')),
          ],
        ),
      ),
    );
  }

  Widget _list(PagedState<Call> s, String agentName) {
    if (s.loading && s.items.isEmpty) return const SkeletonList(padding: EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 20));
    if (s.error != null && s.items.isEmpty) {
      return ErrorState(message: friendlyError(s.error!), onRetry: () => ref.read(callsListProvider.notifier).refresh());
    }
    if (s.items.isEmpty) {
      return EmptyState(
        title: '$agentName hasn\'t made any calls yet.',
        message: 'Start a campaign and every call will show up here.',
        mascot: MascotState.calling,
        actionLabel: 'Call New Leads',
        onAction: () => context.push('/campaign/new'),
      );
    }
    // Group by day header.
    final rows = <Object>[];
    String? lastDay;
    for (final c in s.items) {
      final d = Fmt.friendlyFuture(c.startedAt).split(',').first.split('·').first.trim();
      if (d != lastDay) {
        rows.add(d);
        lastDay = d;
      }
      rows.add(c);
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(callsListProvider.notifier).refresh(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 28),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return s.hasMore
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : const SizedBox(height: 8);
          }
          final r = rows[i];
          if (r is String) return SectionLabel(r, padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 18, 4, 10));
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CallCard(call: r as Call),
          );
        },
      ),
    );
  }
}

class CallCard extends StatelessWidget {
  const CallCard({super.key, required this.call});
  final Call call;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = call;
    final connected = c.status.isConnected;
    return RepaintBoundary(
      child: AppCard(
        padding: const EdgeInsets.all(16),
        onTap: () => context.push(connected ? '/calls/${c.id}/result' : '/calls/${c.id}'),
        semanticLabel: '${Fmt.time(c.startedAt)}, ${c.leadName}, ${c.status.label}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Text(Fmt.time(c.startedAt), style: t.labelMedium?.copyWith(color: AppColors.inkFaint)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.leadName, style: t.titleSmall, overflow: TextOverflow.ellipsis),
                      ),
                      if (c.leadScore != null) ScoreBadge(score: c.leadScore),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        connected ? Icons.check_circle_rounded : Icons.phone_missed_rounded,
                        size: 16,
                        color: connected ? AppColors.success : AppColors.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        connected ? 'Connected · ${Fmt.duration(c.duration)}' : c.status.label,
                        style: t.labelMedium?.copyWith(color: connected ? AppColors.success : AppColors.inkFaint),
                      ),
                    ],
                  ),
                  if (c.nextAction != NextAction.none) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Next: ',
                            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: c.nextAction.label,
                            style: t.bodySmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

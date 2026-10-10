import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';
import '../campaign/campaign_widgets.dart';
import 'leads_controller.dart';
import 'lead_card.dart';
import '../../core/widgets/brand_widgets.dart';

/// Leads – "Who should I care about?" (sorted hot → warm → new → cold)
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, this.initialFilter});
  final String? initialFilter;
  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  static LeadFilter? parseFilter(String? s) => switch (s) {
    'hot' => LeadFilter.hot,
    'warm' => LeadFilter.warm,
    'new' => LeadFilter.newLeads,
    'called' => LeadFilter.called,
    'callback' => LeadFilter.callback,
    'all' => LeadFilter.all,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _applyInitial();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(leadsListProvider.notifier).loadMore();
      }
    });
  }

  void _applyInitial() {
    final f = parseFilter(widget.initialFilter);
    if (f != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(leadQueryProvider.notifier).setFilter(f),
      );
    }
  }

  @override
  void didUpdateWidget(covariant LeadsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialFilter != widget.initialFilter) _applyInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final q = ref.watch(leadQueryProvider);
    final st = ref.watch(leadsListProvider);
    final newCount = ref.watch(dashboardProvider).value?.newLeadsReady ?? 0;
    final showCta =
        newCount > 0 &&
        st.items.isNotEmpty &&
        (q.filter == LeadFilter.all || q.filter == LeadFilter.newLeads) &&
        q.search.isEmpty;
    final filters = [
      (LeadFilter.all, s.filterAll, null),
      (LeadFilter.newLeads, s.filterNew, null),
      (LeadFilter.called, s.filterCalled, null),
      (LeadFilter.hot, s.filterHot, Icons.local_fire_department_rounded),
      (LeadFilter.warm, s.filterWarm, null),
      (LeadFilter.callback, s.filterCallback, null),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: GradientText(
                        s.leadsTitle,
                        style: t.headlineMedium,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.base),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, child: c),
                    ),
                    child: showCta
                        ? Padding(
                            key: const ValueKey('cta'),
                            padding: const EdgeInsets.only(right: 4),
                            child: CallNewLeadsButton(
                              count: newCount,
                              compact: true,
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                  IconButton(
                    key: const Key('leads-get-automatically'),
                    tooltip: s.getLeadsAutomatically,
                    onPressed: () => context.push('/leads/auto'),
                    icon: const Icon(Icons.bolt_rounded),
                  ),
                  IconButton(
                    tooltip: s.addOrImportLeads,
                    onPressed: () => context.push('/leads/import'),
                    icon: const Icon(Icons.person_add_alt_outlined),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                12,
                AppSpace.page,
                0,
              ),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: s.searchLeadsHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.clear,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            ref.read(leadQueryProvider.notifier).setSearch('');
                            setState(() {});
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (v) {
                  setState(() {});
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => ref.read(leadQueryProvider.notifier).setSearch(v),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            FilterChipRow(
              children: [
                for (final (f, label, icon) in filters)
                  AppFilterChip(
                    label: label,
                    icon: icon,
                    iconColor: AppColors.hot,
                    selected: q.filter == f,
                    onSelected: () =>
                        ref.read(leadQueryProvider.notifier).setFilter(f),
                  ),
              ],
            ),
            Expanded(child: _body(context, st, q)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PagedState<Lead> st, LeadQuery q) {
    final s = context.s;
    final Widget child;
    if (st.loading && st.items.isEmpty) {
      child = const SkeletonList(
        key: ValueKey('loading'),
        padding: EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 20),
      );
    } else if (st.error != null && st.items.isEmpty) {
      child = ErrorState(
        key: const ValueKey('error'),
        message: friendlyError(st.error!, s),
        onRetry: () => ref.read(leadsListProvider.notifier).refresh(),
      );
    } else if (st.items.isEmpty) {
      child = KeyedSubtree(
        key: ValueKey('empty-${q.filter}-${q.search}'),
        child: _empty(context, q),
      );
    } else {
      child = RefreshIndicator(
        key: const ValueKey('list'),
        color: AppColors.brand,
        backgroundColor: AppColors.surface,
        onRefresh: () =>
            ref.read(leadsListProvider.notifier).refresh(silent: true),
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            4,
            AppSpace.page,
            28,
          ),
          itemCount: st.items.length + 1,
          itemBuilder: (context, i) {
            if (i == st.items.length) {
              return st.hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : const SizedBox(height: 12);
            }
            final lead = st.items[i];
            return Reveal(
              key: ValueKey(lead.id),
              id: 'lead-${q.filter.name}-${q.search}-${lead.id}',
              index: i < 10 ? i : 0,
              child: LeadCard(
                lead: lead,
                first: i == 0,
                last: i == st.items.length - 1,
              ),
            );
          },
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.base),
      switchInCurve: AppMotion.standard,
      child: child,
    );
  }

  Widget _empty(BuildContext context, LeadQuery q) {
    final s = context.s;
    if (q.search.isNotEmpty) {
      return EmptyState(
        title: s.noMatches,
        message: s.noLeadsMatch(q.search),
        mascot: MascotState.thinking,
      );
    }
    if (q.filter == LeadFilter.hot) {
      return EmptyState(
        title: s.noHotLeadsYet,
        message: s.hotLeadsAppearAfterCalls,
        mascot: MascotState.thinking,
      );
    }
    if (q.filter != LeadFilter.all) {
      return EmptyState(
        title: s.noLeadsHere,
        message: s.noLeadsForFilter,
        mascot: MascotState.thinking,
      );
    }
    return EmptyState(
      title: s.noLeadsHere,
      message: s.addLeadsToStart,
      actionLabel: s.addLeads,
      onAction: () => context.push('/leads/import'),
    );
  }
}

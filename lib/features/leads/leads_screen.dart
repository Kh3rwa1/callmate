import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/widgets/app_card.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../campaign/campaign_widgets.dart';
import 'leads_controller.dart';
import 'lead_card.dart';

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

  static const _filters = [
    (LeadFilter.all, 'All'),
    (LeadFilter.newLeads, 'New'),
    (LeadFilter.called, 'Called'),
    (LeadFilter.hot, 'Hot'),
    (LeadFilter.warm, 'Warm'),
    (LeadFilter.callback, 'Callback'),
  ];

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
    final t = Theme.of(context).textTheme;
    final q = ref.watch(leadQueryProvider);
    final s = ref.watch(leadsListProvider);
    final newCount = ref.watch(dashboardProvider).value?.newLeadsReady ?? 0;

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
                      child: Text('Leads', style: t.headlineMedium),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add or import leads',
                    onPressed: () => context.push('/leads/import'),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
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
                  hintText: 'Search name, phone or interest',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
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
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.page,
                  vertical: 12,
                ),
                children: [
                  for (final (f, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppFilterChip(
                        label: label,
                        selected: q.filter == f,
                        icon: f == LeadFilter.hot
                            ? Icons.local_fire_department_rounded
                            : null,
                        iconColor: AppColors.hot,
                        onSelected: () =>
                            ref.read(leadQueryProvider.notifier).setFilter(f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _body(s, q, newCount)),
          ],
        ),
      ),
    );
  }

  Widget _body(PagedState<Lead> s, LeadQuery q, int newCount) {
    if (s.loading && s.items.isEmpty) {
      return const SkeletonList(
        padding: EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 20),
      );
    }
    if (s.error != null && s.items.isEmpty) {
      return ErrorState(
        message: friendlyError(s.error!),
        onRetry: () => ref.read(leadsListProvider.notifier).refresh(),
      );
    }
    if (s.items.isEmpty) {
      if (q.search.isNotEmpty) {
        return EmptyState(
          title: 'No matches',
          message: 'No leads match “${q.search}”.',
          mascot: MascotState.thinking,
        );
      }
      if (q.filter == LeadFilter.hot) {
        return const EmptyState(
          title: 'No hot leads yet',
          message:
              'Your AI employee will flag leads that are ready to buy or book.',
          mascot: MascotState.thinking,
        );
      }
      return EmptyState(
        title: 'No leads here',
        message:
            'Your AI employee is ready. Add your first leads to start calling.',
        actionLabel: 'Add leads',
        onAction: () => context.push('/leads/import'),
      );
    }
    final showCta =
        newCount > 0 &&
        (q.filter == LeadFilter.all || q.filter == LeadFilter.newLeads) &&
        q.search.isEmpty;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(leadsListProvider.notifier).refresh(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 28),
        itemCount: s.items.length + (showCta ? 1 : 0) + 1,
        itemBuilder: (context, i) {
          if (showCta && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CallNewLeadsButton(count: newCount),
            );
          }
          final idx = i - (showCta ? 1 : 0);
          if (idx == s.items.length) {
            return s.hasMore
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : const SizedBox(height: 12);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Reveal(
              index: idx < 10 ? idx : 0,
              child: LeadCard(lead: s.items[idx]),
            ),
          );
        },
      ),
    );
  }
}

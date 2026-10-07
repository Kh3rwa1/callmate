import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
    this.cursor,
  });
  final List<T> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;
  final String? cursor;

  PagedState<T> copyWith({
    List<T>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
    String? cursor,
  }) => PagedState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    cursor: cursor ?? this.cursor,
  );
}

class LeadQuery {
  const LeadQuery({this.filter = LeadFilter.all, this.search = ''});
  final LeadFilter filter;
  final String search;
}

final leadQueryProvider = NotifierProvider<LeadQueryController, LeadQuery>(
  LeadQueryController.new,
);

class LeadQueryController extends Notifier<LeadQuery> {
  @override
  LeadQuery build() => const LeadQuery();
  void setFilter(LeadFilter f) =>
      state = LeadQuery(filter: f, search: state.search);
  void setSearch(String s) =>
      state = LeadQuery(filter: state.filter, search: s);
}

/// Paginated leads (20 per page) – never loads the full list at once.
final leadsListProvider = NotifierProvider<LeadsList, PagedState<Lead>>(
  LeadsList.new,
);

class LeadsList extends Notifier<PagedState<Lead>> {
  int _gen = 0;

  @override
  PagedState<Lead> build() {
    ref.watch(leadQueryProvider);
    ref.listen(dataVersionProvider, (_, __) => refresh(silent: true));
    Future.microtask(refresh);
    return const PagedState(loading: true);
  }

  Future<void> refresh({bool silent = false}) async {
    final q = ref.read(leadQueryProvider);
    final gen = ++_gen;
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final keep = silent ? state.items.length.clamp(20, 200) : 20;
      final p = await ref
          .read(leadRepoProvider)
          .list(query: q.search, filter: q.filter, limit: keep);
      if (gen != _gen) return;
      state = PagedState(
        items: p.items,
        hasMore: p.hasMore,
        cursor: p.nextCursor,
      );
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    final q = ref.read(leadQueryProvider);
    final gen = _gen;
    state = state.copyWith(loadingMore: true);
    try {
      final p = await ref
          .read(leadRepoProvider)
          .list(query: q.search, filter: q.filter, cursor: state.cursor);
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

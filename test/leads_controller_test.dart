import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/leads/leads_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lead repository that can be told to fail, wrapping the mock one.
class _FlakyLeadRepository extends MockLeadRepository {
  _FlakyLeadRepository(super.b);
  bool fail = false;
  int listCalls = 0;

  @override
  Future<Page<Lead>> list({
    String? query,
    LeadFilter filter = LeadFilter.all,
    String? cursor,
    int limit = 20,
  }) async {
    listCalls++;
    if (fail) throw StateError('network down');
    return super.list(
      query: query,
      filter: filter,
      cursor: cursor,
      limit: limit,
    );
  }
}

void main() {
  late MockBackend backend;
  late _FlakyLeadRepository repo;
  late ProviderContainer container;

  setUp(() {
    backend = MockBackend();
    repo = _FlakyLeadRepository(backend);
    container = ProviderContainer(
      overrides: [
        useMockProvider.overrideWithValue(true),
        mockBackendProvider.overrideWithValue(backend),
        leadRepoProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  PagedState<Lead> state() => container.read(leadsListProvider);
  LeadsList list() => container.read(leadsListProvider.notifier);

  Future<void> idle() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = state();
      if (!s.loading && !s.loadingMore) return;
    }
    fail('leads list never finished loading');
  }

  group('PagedState', () {
    test('copyWith keeps values and can clear the error', () {
      const s = PagedState<int>(items: [1], error: 'x', cursor: '20');
      final c = s.copyWith(loading: true);
      expect(c.items, [1]);
      expect(c.loading, isTrue);
      expect(c.error, 'x');
      expect(c.cursor, '20');
      expect(c.copyWith(clearError: true).error, isNull);
    });
  });

  group('LeadQueryController', () {
    test('filter and search are independent', () {
      final q = container.read(leadQueryProvider.notifier);
      q.setSearch('riya');
      q.setFilter(LeadFilter.hot);
      final v = container.read(leadQueryProvider);
      expect(v.filter, LeadFilter.hot);
      expect(v.search, 'riya');
    });
  });

  group('LeadsList', () {
    // Keep the auto-refreshing list alive for the whole test. Every test
    // waits for loading to finish before disposal (see report: refresh()
    // does not check ref.mounted after its await).
    setUp(() => container.listen(leadsListProvider, (_, _) {}));

    test('first page loads 20 leads sorted by priority', () async {
      expect(state().loading, isTrue);
      await idle();
      final s = state();
      expect(s.items, hasLength(20));
      expect(s.hasMore, backend.leads.length > 20);
      expect(s.cursor, '20');
      expect(s.error, isNull);
      final sorted = [...s.items]..sort(leadPriority);
      expect(s.items.map((e) => e.id), sorted.map((e) => e.id));
    });

    test('loadMore appends the next page without duplicates', () async {
      await idle();
      final first = state().items.map((e) => e.id).toList();
      await list().loadMore();
      final s = state();
      expect(s.items.length, greaterThan(first.length));
      expect(s.items.take(first.length).map((e) => e.id), first);
      expect(s.items.map((e) => e.id).toSet().length, s.items.length);
      expect(s.loadingMore, isFalse);
    });

    test('loadMore is a no-op when there are no more pages', () async {
      await idle();
      while (state().hasMore) {
        await list().loadMore();
      }
      final calls = repo.listCalls;
      await list().loadMore();
      expect(repo.listCalls, calls);
      expect(state().items.length, backend.leads.length);
    });

    test('filter restricts results', () async {
      container.read(leadQueryProvider.notifier).setFilter(LeadFilter.hot);
      await idle();
      expect(state().items, isNotEmpty);
      expect(state().items.every((l) => l.isHot), isTrue);
    });

    test('search matches by name', () async {
      final target = backend.leads.values.first;
      final term = target.name.split(' ').first.toLowerCase();
      container.read(leadQueryProvider.notifier).setSearch(term);
      await idle();
      expect(state().items.map((e) => e.id), contains(target.id));
      expect(
        state().items.every(
          (l) =>
              l.name.toLowerCase().contains(term) ||
              (l.interest ?? '').toLowerCase().contains(term),
        ),
        isTrue,
      );
    });

    test('search with no match yields an empty last page', () async {
      container.read(leadQueryProvider.notifier).setSearch('zzzz-nobody');
      await idle();
      expect(state().items, isEmpty);
      expect(state().hasMore, isFalse);
    });

    test('refresh failure surfaces the error, retry clears it', () async {
      await idle();
      repo.fail = true;
      await list().refresh();
      expect(state().error, isA<StateError>());
      expect(state().loading, isFalse);

      repo.fail = false;
      await list().refresh();
      expect(state().error, isNull);
      expect(state().items, hasLength(20));
    });

    test('loadMore failure keeps existing items', () async {
      await idle();
      final before = state().items.length;
      repo.fail = true;
      await list().loadMore();
      expect(state().items.length, before);
      expect(state().loadingMore, isFalse);
    });

    test('backend data changes trigger a silent refresh', () async {
      await idle();
      final calls = repo.listCalls;
      container.read(dataVersionProvider.notifier).bump();
      await idle();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(repo.listCalls, greaterThan(calls));
      expect(state().loading, isFalse);
    });
  });
}

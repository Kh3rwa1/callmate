import 'dart:async';
import 'dart:convert';

import 'package:callpilot/core/network/response_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _Offline implements Exception {}

bool _isOffline(Object e) => e is _Offline;

void main() {
  late MemoryResponseStore store;
  late ResponseCache cache;
  late int repaints;

  setUp(() {
    store = MemoryResponseStore();
    repaints = 0;
    cache = ResponseCache(
      store,
      debounce: Duration.zero,
      onRefreshed: () => repaints++,
    );
  });

  test(
    'first launch with nothing saved waits for the network and saves it',
    () async {
      final v = await cache.get(
        '/dashboard/today',
        () async => {'calls': 3},
        isOffline: _isOffline,
      );
      expect(v, {'calls': 3});
      await pumpEventQueue();
      expect(jsonDecode(store.data['/dashboard/today']!), {'calls': 3});
    },
  );

  test('next launch shows the saved copy at once, then repaints once fresh '
      'data differs', () async {
    store.data['/dashboard/today'] = jsonEncode({'calls': 3});
    final net = Completer<Object?>();
    final v = await cache.get(
      '/dashboard/today',
      () => net.future,
      isOffline: _isOffline,
    );
    expect(v, {'calls': 3}, reason: 'no waiting for the network');
    net.complete({'calls': 5});
    await pumpEventQueue();
    expect(repaints, 1);
    // The repaint reads the fresh answer without another request.
    var asked = 0;
    final again = await cache.get('/dashboard/today', () async {
      asked++;
      return {'calls': 99};
    }, isOffline: _isOffline);
    expect(again, {'calls': 5});
    expect(asked, 0);
  });

  test('no repaint when the background answer is unchanged', () async {
    store.data['/usage'] = jsonEncode({'left': 10});
    await cache.get('/usage', () async => {'left': 10}, isOffline: _isOffline);
    await pumpEventQueue();
    expect(repaints, 0);
  });

  test('offline: the saved copy is shown instead of an error', () async {
    store.data['/followups'] = jsonEncode([1, 2]);
    // Use up the "first open" so this read goes to the network.
    await cache.get('/followups', () async => [1, 2], isOffline: _isOffline);
    cache.markStale();
    final v = await cache.get(
      '/followups',
      () async => throw _Offline(),
      isOffline: _isOffline,
    );
    expect(v, [1, 2]);
  });

  test('real server errors are not hidden by the saved copy', () async {
    store.data['/leads'] = jsonEncode([1]);
    await cache.get('/leads', () async => [1], isOffline: _isOffline);
    cache.markStale();
    expect(
      cache.get(
        '/leads',
        () async => throw StateError('500'),
        isOffline: _isOffline,
      ),
      throwsStateError,
    );
  });

  test('after an edit the next read goes to the network', () async {
    var n = 0;
    Future<Object?> fetch() async => {'n': ++n};
    expect(await cache.get('/agent', fetch, isOffline: _isOffline), {'n': 1});
    expect(await cache.get('/agent', fetch, isOffline: _isOffline), {
      'n': 1,
    }, reason: 'fresh copy reused for a moment');
    cache.markStale();
    expect(await cache.get('/agent', fetch, isOffline: _isOffline), {'n': 2});
  });

  test('two screens asking at once share one request', () async {
    var asked = 0;
    final net = Completer<Object?>();
    Future<Object?> fetch() {
      asked++;
      return net.future;
    }

    final a = cache.get('/business', fetch, isOffline: _isOffline);
    final b = cache.get('/business', fetch, isOffline: _isOffline);
    net.complete({'name': 'Sunrise'});
    expect(await a, {'name': 'Sunrise'});
    expect(await b, {'name': 'Sunrise'});
    expect(asked, 1);
  });

  test('sign-out wipes everything saved', () async {
    store.data['/business'] = jsonEncode({'name': 'Old shop'});
    await cache.clear();
    expect(store.data, isEmpty);
    final v = await cache.get(
      '/business',
      () async => {'name': 'New shop'},
      isOffline: _isOffline,
    );
    expect(v, {'name': 'New shop'});
  });

  test('auth and voice are never cached', () {
    expect(ResponseCache.cacheable('/auth/me'), isFalse);
    expect(ResponseCache.cacheable('/voice/session'), isFalse);
    expect(ResponseCache.cacheable('/dashboard/today'), isTrue);
  });

  test('query order does not split the cache', () {
    expect(
      ResponseCache.keyFor('/calls', {'b': 2, 'a': 1}),
      ResponseCache.keyFor('/calls', {'a': 1, 'b': 2}),
    );
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where the last good answer to each GET is kept between app launches.
///
/// Values are the server's raw JSON, so every model keeps parsing through
/// its own repository code. Nothing here is a secret (it is the owner's own
/// business data on their own phone), but it is wiped on sign-out so the
/// next account never sees it.
abstract class ResponseStore {
  Future<String?> read(String key);
  Future<void> write(String key, String json);
  Future<void> clear();
}

/// One small file per request under the app's private support directory.
class FileResponseStore implements ResponseStore {
  FileResponseStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _dir;
  Directory? _root;

  /// Big lists aren't worth the disk; screens just load them normally.
  static const maxBytes = 512 * 1024;

  Future<Directory> _folder() async {
    if (_root != null) return _root!;
    final d = Directory('${(await _dir()).path}/api_cache');
    if (!d.existsSync()) await d.create(recursive: true);
    return _root = d;
  }

  Future<File> _file(String key) async {
    final name = sha1.convert(utf8.encode(key)).toString();
    return File('${(await _folder()).path}/$name.json');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final f = await _file(key);
      return f.existsSync() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String json) async {
    if (json.length > maxBytes) return;
    try {
      final f = await _file(key);
      // Write then rename, so a crash mid-write never leaves half a file.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final d = await _folder();
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
    _root = null;
  }
}

/// In-memory store for tests.
@visibleForTesting
class MemoryResponseStore implements ResponseStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String json) async => data[key] = json;
  @override
  Future<void> clear() async => data.clear();
}

/// Makes reads feel instant on slow Indian mobile networks:
///
/// * **First open of a screen this session**: if a saved copy exists it is
///   shown at once, and the network is asked in the background. When the
///   answer differs, [onRefreshed] fires (debounced, so a dozen screens
///   updating on launch cause one repaint, not a dozen).
/// * **No network**: the saved copy is shown instead of an error.
/// * **Two screens asking the same thing at once** share one request.
/// * **Any write or server push** ([markStale]) makes the next read go to
///   the network, so the owner never sees data from before their own edit.
class ResponseCache {
  ResponseCache(
    this.store, {
    this.onRefreshed,
    this.freshFor = const Duration(seconds: 20),
    this.debounce = const Duration(milliseconds: 350),
  });

  final ResponseStore store;

  /// Called after background refreshes brought new data.
  VoidCallback? onRefreshed;

  /// How long a just-fetched answer is reused without asking again (covers
  /// the repaint that [onRefreshed] triggers).
  final Duration freshFor;
  final Duration debounce;

  final _fresh = <String, (DateTime, Object?)>{};
  final _inFlight = <String, (int, Future<Object?>)>{};
  final _seenThisSession = <String>{};
  int _epoch = 0;
  bool _pendingRefresh = false;

  /// Reads that must always hit the network.
  static bool cacheable(String path) =>
      !path.startsWith('/auth') &&
      !path.startsWith('/voice') &&
      !path.startsWith('/billing/checkout') &&
      !path.startsWith('/devices');

  static String keyFor(String path, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return path;
    final q = query.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return '$path?${q.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  /// The raw JSON for [key]: saved copy, fresh copy or network, per the
  /// rules above. [fetch] does the real request.
  Future<Object?> get(
    String key,
    Future<Object?> Function() fetch, {
    required bool Function(Object error) isOffline,
  }) async {
    final hit = _fresh[key];
    if (hit != null && DateTime.now().difference(hit.$1) < freshFor) {
      return hit.$2;
    }

    if (_seenThisSession.add(key)) {
      final saved = await _readSaved(key);
      if (saved != null) {
        _refreshInBackground(key, fetch, saved);
        return saved.$2;
      }
    }

    try {
      return await _network(key, fetch);
    } catch (e) {
      if (isOffline(e)) {
        final saved = await _readSaved(key);
        if (saved != null) return saved.$2;
      }
      rethrow;
    }
  }

  /// Something changed on the server; the next reads must be real.
  void markStale() {
    _epoch++;
    _fresh.clear();
  }

  Future<void> clear() async {
    markStale();
    _seenThisSession.clear();
    _inFlight.clear();
    await store.clear();
  }

  Future<(String, Object?)?> _readSaved(String key) async {
    final raw = await store.read(key);
    if (raw == null) return null;
    try {
      return (raw, jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _network(String key, Future<Object?> Function() fetch) {
    final epoch = _epoch;
    // Share a request only if nothing changed since it started.
    final running = _inFlight[key];
    if (running != null && running.$1 == epoch) return running.$2;
    final f = fetch()
        .then((data) {
          // A write landed while this was in flight: don't let the older
          // answer pose as fresh.
          if (epoch == _epoch) _fresh[key] = (DateTime.now(), data);
          _save(key, data);
          return data;
        })
        // Block body: returning the removed Future here would make this
        // future wait on itself.
        .whenComplete(() {
          if (_inFlight[key]?.$1 == epoch) _inFlight.remove(key);
        });
    _inFlight[key] = (epoch, f);
    return f;
  }

  void _save(String key, Object? data) {
    try {
      store.write(key, jsonEncode(data));
    } catch (_) {}
  }

  void _refreshInBackground(
    String key,
    Future<Object?> Function() fetch,
    (String, Object?) saved,
  ) {
    _network(key, fetch)
        .then((data) {
          String? now;
          try {
            now = jsonEncode(data);
          } catch (_) {}
          if (now != saved.$1) _scheduleRefresh();
        })
        .catchError((Object _) {});
  }

  void _scheduleRefresh() {
    if (_pendingRefresh) return;
    _pendingRefresh = true;
    Future<void>.delayed(debounce, () {
      _pendingRefresh = false;
      onRefreshed?.call();
    });
  }
}

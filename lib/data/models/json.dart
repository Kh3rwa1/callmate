/// Tiny, defensive JSON helpers. Backend data is never trusted to be
/// well-typed: every read is null-safe so a malformed field can't crash a screen.
library;

typedef Json = Map<String, dynamic>;

String jStr(Json j, String k, [String fallback = '']) {
  final v = j[k];
  if (v == null) return fallback;
  return v.toString();
}

String? jStrN(Json j, String k) {
  final v = j[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int jInt(Json j, String k, [int fallback = 0]) {
  final v = j[k];
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? jIntN(Json j, String k) {
  final v = j[k];
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

double jDouble(Json j, String k, [double fallback = 0]) {
  final v = j[k];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool jBool(Json j, String k, [bool fallback = false]) {
  final v = j[k];
  if (v is bool) return v;
  if (v is String) return v == 'true';
  if (v is num) return v != 0;
  return fallback;
}

/// `YYYY-MM-DD HH:MM[:SS[.fff]]` with no zone: SQLite `datetime('now')`,
/// which is UTC.
final _naiveDateTime = RegExp(
  r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$',
);

DateTime? jDate(Json j, String k) {
  final v = j[k];
  if (v is String) {
    final utc = _naiveDateTime.hasMatch(v) ? '${v.replaceFirst(' ', 'T')}Z' : v;
    return DateTime.tryParse(utc)?.toLocal();
  }
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}

List<String> jStrList(Json j, String k) {
  final v = j[k];
  if (v is List) {
    return v.where((e) => e != null).map((e) => e.toString()).toList();
  }
  return const [];
}

List<T> jList<T>(Json j, String k, T Function(Json) f) {
  final v = j[k];
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => f(Map<String, dynamic>.from(e)))
        .toList();
  }
  return const [];
}

Json? jObj(Json j, String k) {
  final v = j[k];
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

String? dateOut(DateTime? d) => d?.toUtc().toIso8601String();

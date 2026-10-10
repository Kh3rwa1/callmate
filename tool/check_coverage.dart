import 'dart:io';

// Coverage ratchet for `flutter test --coverage` (reads coverage/lcov.info).
//
// Thresholds sit ~2 points under the measured baseline so normal churn passes
// but a real regression fails CI. Baseline measured 2026-10-10 (lead integrations):
//   lib/data 95.16%, lib/services 56.50%, data+services 85.85%,
//   lib/ (excl. l10n + generated) 91.47%.
// Raise these when coverage improves; never lower them to land a PR.
//
// Run with plain `dart tool/check_coverage.dart` (only needs dart:io).

/// Minimum line coverage for lib/data + lib/services combined.
const minDataAndServices = 83.5;

/// Minimum line coverage for lib/services on its own (weakest area; floor so
/// it cannot silently get worse while lib/data carries the combined number).
const minServices = 54.5;

/// Minimum line coverage for everything under lib/, excluding string tables
/// (lib/l10n) and generated code, which would otherwise distort the number.
const minOverall = 89.5;

/// Files left out of the overall bucket.
bool _excluded(String path) =>
    path.contains('lib/l10n/') ||
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.gr.dart') ||
    path.endsWith('.mocks.dart');

class _Bucket {
  int found = 0;
  int hit = 0;
  double get pct => found == 0 ? 0 : hit / found * 100;
  void add(bool covered) {
    found++;
    if (covered) hit++;
  }

  String describe() => '${pct.toStringAsFixed(2)}% ($hit / $found lines)';
}

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info not found. Please run flutter test --coverage first.',
    );
    exit(1);
  }

  final data = _Bucket();
  final services = _Bucket();
  final combined = _Bucket();
  final overall = _Bucket();
  final raw = _Bucket();

  var currentFile = '';
  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).trim().replaceAll(r'\', '/');
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length < 2 || !currentFile.contains('lib/')) continue;
      final covered = (int.tryParse(parts[1]) ?? 0) > 0;
      raw.add(covered);
      if (_excluded(currentFile)) continue;
      overall.add(covered);
      if (currentFile.contains('lib/data/')) {
        data.add(covered);
        combined.add(covered);
      } else if (currentFile.contains('lib/services/')) {
        services.add(covered);
        combined.add(covered);
      }
    }
  }

  const rule = '------------------------------------------------------------';
  stdout
    ..writeln(rule)
    ..writeln('Flutter Line Coverage Report:')
    ..writeln('  lib/data:     ${data.describe()}')
    ..writeln('  lib/services: ${services.describe()}')
    ..writeln('  Combined:     ${combined.describe()}')
    ..writeln('  lib/ gated:   ${overall.describe()}  (excl. l10n/generated)')
    ..writeln('  lib/ raw:     ${raw.describe()}  (informational)')
    ..writeln(rule);

  final failures = <String>[
    if (combined.pct < minDataAndServices)
      'Combined data+services coverage (${combined.pct.toStringAsFixed(2)}%) '
          'is below the required $minDataAndServices% threshold.',
    if (services.pct < minServices)
      'lib/services coverage (${services.pct.toStringAsFixed(2)}%) is below '
          'the required $minServices% threshold.',
    if (overall.pct < minOverall)
      'Overall lib/ coverage (${overall.pct.toStringAsFixed(2)}%) is below '
          'the required $minOverall% threshold.',
  ];
  if (failures.isNotEmpty) {
    for (final f in failures) {
      stderr.writeln('ERROR: $f');
    }
    exit(1);
  }
  stdout.writeln(
    'SUCCESS: coverage meets the thresholds (data+services >= '
    '$minDataAndServices%, services >= $minServices%, lib/ >= $minOverall%).',
  );
}

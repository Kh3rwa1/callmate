import 'dart:io';

/// Minimum line coverage for lib/data + lib/services combined.
const minDataAndServices = 80.0;

/// Minimum line coverage for everything under lib/.
const minOverall = 85.0;

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

  var currentFile = '';
  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).trim().replaceAll(r'\', '/');
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length < 2 || !currentFile.contains('lib/')) continue;
      final covered = (int.tryParse(parts[1]) ?? 0) > 0;
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
    ..writeln('  lib/ overall: ${overall.describe()}')
    ..writeln(rule);

  final failures = <String>[
    if (combined.pct < minDataAndServices)
      'Combined data+services coverage (${combined.pct.toStringAsFixed(2)}%) '
          'is below the required $minDataAndServices% threshold.',
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
    'SUCCESS: coverage meets the thresholds '
    '(data+services >= $minDataAndServices%, lib/ >= $minOverall%).',
  );
}

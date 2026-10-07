import 'dart:io';

void main() {
  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info not found. Please run flutter test --coverage first.',
    );
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();
  int dataFound = 0;
  int dataHit = 0;
  int servFound = 0;
  int servHit = 0;

  String currentFile = '';

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).trim();
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        final hit = int.tryParse(parts[1]) ?? 0;
        if (currentFile.contains('lib/data/')) {
          dataFound++;
          if (hit > 0) dataHit++;
        } else if (currentFile.contains('lib/services/')) {
          servFound++;
          if (hit > 0) servHit++;
        }
      }
    }
  }

  final totalFound = dataFound + servFound;
  final totalHit = dataHit + servHit;
  final pct = totalFound == 0 ? 0.0 : (totalHit / totalFound) * 100;

  final dataPct = dataFound == 0 ? 0.0 : (dataHit / dataFound) * 100;
  final servPct = servFound == 0 ? 0.0 : (servHit / servFound) * 100;

  stdout.writeln(
    '------------------------------------------------------------',
  );
  stdout.writeln('Flutter Line Coverage Report:');
  stdout.writeln(
    '  lib/data:     ${dataPct.toStringAsFixed(2)}% ($dataHit / $dataFound lines)',
  );
  stdout.writeln(
    '  lib/services: ${servPct.toStringAsFixed(2)}% ($servHit / $servFound lines)',
  );
  stdout.writeln(
    '  Combined:     ${pct.toStringAsFixed(2)}% ($totalHit / $totalFound lines)',
  );
  stdout.writeln(
    '------------------------------------------------------------',
  );

  const minRequired = 60.0;
  if (pct < minRequired) {
    stderr.writeln(
      'ERROR: Combined coverage (${pct.toStringAsFixed(2)}%) is below the required $minRequired% threshold.',
    );
    exit(1);
  } else {
    stdout.writeln(
      'SUCCESS: Combined coverage (${pct.toStringAsFixed(2)}%) meets the $minRequired% threshold.',
    );
  }
}

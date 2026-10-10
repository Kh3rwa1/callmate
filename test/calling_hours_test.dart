import 'package:callpilot/core/utils/calling_hours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('traiCallingHours', () {
    test('keeps a window already inside 09:00-21:00', () {
      expect(traiCallingHours(10, 19), const RangeValues(10, 19));
      expect(traiCallingHours(9, 21), const RangeValues(9, 21));
    });

    test('clamps legacy windows into the TRAI limits', () {
      expect(traiCallingHours(0, 24), const RangeValues(9, 21));
      expect(traiCallingHours(8, 22), const RangeValues(9, 21));
    });

    test('never returns an empty or inverted window', () {
      final late = traiCallingHours(22, 23);
      expect(late.start, lessThan(late.end));
      expect(late.end, kTraiLatestHour);
      final inverted = traiCallingHours(15, 12);
      expect(inverted.start, lessThan(inverted.end));
    });
  });
}

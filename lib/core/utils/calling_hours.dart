import 'package:flutter/material.dart';

/// TRAI: commercial calls only between 09:00 and 21:00 in the lead's local
/// time. The backend enforces the same window; pickers never offer more.
const int kTraiEarliestHour = 9;

/// Exclusive end hour: calls are allowed while the hour is before 21:00.
const int kTraiLatestHour = 21;

/// Picker range for a calling window, clamped to the TRAI window (older
/// accounts may have stored hours outside it).
RangeValues traiCallingHours(int start, int end) {
  final s = start.clamp(kTraiEarliestHour, kTraiLatestHour - 1);
  final e = end.clamp(s + 1, kTraiLatestHour);
  return RangeValues(s.toDouble(), e.toDouble());
}

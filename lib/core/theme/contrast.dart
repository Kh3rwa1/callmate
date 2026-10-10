import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.x contrast helpers, used by the design-token tests so colour
/// changes can't silently drop below AA.
class Contrast {
  const Contrast._();

  /// AA for normal text.
  static const aa = 4.5;

  /// AA for large text (≥ 24 px, or ≥ 18.66 px bold) and UI glyphs.
  static const aaLarge = 3.0;

  static double _channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// Relative luminance of an opaque colour.
  static double luminance(Color c) =>
      0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

  /// Contrast ratio between two opaque colours (1–21).
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
}

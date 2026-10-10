import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text that wraps between words but never inside one.
///
/// At big text sizes a long word ("Automobile", "कर्मचारी") can be wider than
/// its box, and Flutter then splits it mid-word ("Automobil / e"). This
/// measures the widest word and, only if it would not fit, shrinks the text
/// scale just enough that it does.
///
/// Pass [width] when the box width is known up front (e.g. inside an
/// [IntrinsicHeight], where a [LayoutBuilder] can't be used); otherwise the
/// width is measured with a [LayoutBuilder].
class WholeWordText extends StatelessWidget {
  const WholeWordText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.textAlign,
    this.width,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final double? width;

  /// The text scale factor at which every word of [text] fits in [width].
  static double fitScale(
    String text,
    TextStyle? style,
    double width,
    double scale,
    TextDirection direction,
  ) {
    if (!width.isFinite || width <= 0) return scale;
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: direction,
        textScaler: TextScaler.linear(scale),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    if (widest <= width) return scale;
    // A hair under, so rounding never tips the word over the edge.
    return scale * (width / widest) * 0.99;
  }

  Widget _text(BuildContext context, double w) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final fit = fitScale(
      text,
      base,
      w,
      MediaQuery.textScalerOf(context).scale(100) / 100,
      Directionality.of(context),
    );
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.linear(fit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = width;
    if (w != null) return _text(context, w);
    return LayoutBuilder(builder: (context, c) => _text(context, c.maxWidth));
  }
}

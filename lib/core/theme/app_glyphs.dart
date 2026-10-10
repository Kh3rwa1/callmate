import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// CallPilot's own icon set: 24×24, 1.75 stroke, round caps and joins –
/// the same soft, rounded hand as the bird mascot. Files live in
/// `assets/icons/<name>.svg`; they are drawn in black and tinted at runtime.
///
/// Stock Material icons remain for the long tail (settings rows, chevrons);
/// everything the owner taps often uses these.
enum AppGlyphs {
  // Tabs
  home,
  customers,
  call,
  message,
  employee,
  // Key actions
  hot,
  callback,
  teach,
  help,
  alerts,
  plan,
  add,
  share,
  qr;

  String get asset => 'assets/icons/$name.svg';
}

/// One [AppGlyphs] icon. Takes colour and size from [IconTheme] by default
/// so it drops in wherever an [Icon] did.
class AppGlyph extends StatelessWidget {
  const AppGlyph(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AppGlyphs glyph;
  final double? size;
  final Color? color;

  /// Read by screen readers; null hides the glyph (decorative).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? const Color(0xFF000000);
    final svg = SvgPicture.asset(
      glyph.asset,
      width: s,
      height: s,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: semanticLabel == null,
      child: SizedBox.square(dimension: s, child: svg),
    );
  }
}

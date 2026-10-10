import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../theme/app_colors.dart';

/// CallPilot logo mark (uses the launcher icon asset).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.26),
    child: Image.asset(
      'assets/icon/app_icon.png',
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: Brand.appName,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: AppColors.brandFill,
        child: Icon(Icons.call_rounded, color: Colors.white, size: size * 0.55),
      ),
    ),
  );
}

/// "CallPilot" wordmark – always exact capitalization from [Brand.appName].
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.size = 18,
    this.showMark = true,
    this.color,
  });
  final double size;
  final bool showMark;

  /// Defaults to [AppColors.ink].
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showMark) ...[
        BrandMark(size: size * 1.9),
        SizedBox(width: size * 0.55),
      ],
      Text(
        Brand.appName,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.ink,
          letterSpacing: -0.3,
        ),
      ),
    ],
  );
}

/// Text painted with [AppColors.titleGradient] – used for page titles so
/// headings carry the brand instead of plain ink.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.colors,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors ?? AppColors.titleGradient,
    ).createShader(Offset.zero & bounds.size),
    child: Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    ),
  );
}

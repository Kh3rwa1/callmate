import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// The top of a tab, painted edge to edge in the tab's [AppWorld] colour
/// (under the status bar too), with rounded bottom corners so the paper
/// page below reads as a sheet tucked under it.
///
/// Text and icons inside default to the world's foreground colour.
class WorldHeader extends StatelessWidget {
  const WorldHeader({
    super.key,
    required this.world,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.page,
      8,
      AppSpace.page,
      AppSpace.xl,
    ),
  });

  final AppWorld world;
  final Widget child;

  /// Inside padding; the status bar height is added on top.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final t = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (world.isDarkBg
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: world.paint,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(32),
          ),
        ),
        padding: padding.copyWith(top: padding.top + top),
        child: IconTheme(
          data: IconThemeData(color: world.fg),
          child: DefaultTextStyle.merge(
            style: (t.bodyLarge ?? const TextStyle()).copyWith(color: world.fg),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The tab's serif title, with an optional small eyebrow above it and
/// actions on the right.
class WorldTitle extends StatelessWidget {
  const WorldTitle({
    super.key,
    required this.world,
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.size = 44,
  });

  final AppWorld world;
  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.eyebrow(color: world.soft),
              ),
              const SizedBox(height: 6),
            ],
            Semantics(
              header: true,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.4,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(size, color: world.fg, height: 1.0),
                ),
              ),
            ),
          ],
        ),
      ),
      ...actions,
    ],
  );
}

/// A poster-sized number with a two-line uppercase label beside it:
///
///     110  CALLS
///          TODAY
class BigStat extends StatelessWidget {
  const BigStat({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.labelColor,
    this.size = 88,
    this.countUp = false,
    this.semanticsLabel,
    this.countKey,
  });

  /// Key on the number itself (absent while loading).
  final Key? countKey;

  /// null shows a quiet placeholder (still loading) – never a fake "0".
  final int? value;
  final String label;
  final Color color;
  final Color? labelColor;
  final double size;
  final bool countUp;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final style = AppTheme.number(size, color: color, height: 0.92);
    return Semantics(
      label: semanticsLabel ?? (v == null ? null : '${Fmt.number(v)} $label'),
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (v == null)
              Container(
                width: size * 0.9,
                height: size * 0.8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              )
            else
              AnimatedCount(
                key: countKey,
                value: v,
                countUp: countUp,
                format: Fmt.number,
                style: style,
              ),
            const SizedBox(width: 12),
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(bottom: size * 0.07),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final text = label.toUpperCase();
                    final style = AppTheme.eyebrow(
                      color: labelColor ?? color,
                      size: 15,
                    ).copyWith(height: 1.15, letterSpacing: 1.4);
                    // Shrink just enough that the longest word fits, so a
                    // big text size never breaks "TODAY" into "TODA".
                    final scaler = MediaQuery.textScalerOf(context);
                    var widest = 0.0;
                    for (final w in text.split(' ')) {
                      final tp = TextPainter(
                        text: TextSpan(text: w, style: style),
                        textScaler: scaler,
                        textDirection: Directionality.of(context),
                        maxLines: 1,
                      )..layout();
                      widest = math.max(widest, tp.width);
                      tp.dispose();
                    }
                    // A little slack: glyph advances round differently at
                    // the shrunken size.
                    final room = c.maxWidth - 2;
                    final k = widest > room && widest > 0 ? room / widest : 1.0;
                    return Text(
                      text,
                      maxLines: 2,
                      style: style.copyWith(
                        fontSize: 15 * k,
                        letterSpacing: 1.4 * k,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round, tinted icon button for a world header (help, alerts, add…),
/// with a short word under it so owners never guess what an icon does.
class WorldAction extends StatelessWidget {
  const WorldAction({
    super.key,
    required this.world,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  final AppWorld world;
  final Widget icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel ?? label,
    excludeSemantics: true,
    child: Pressable(
      onTap: onTap,
      scale: 0.9,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52, maxWidth: 68),
        child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: world.fg.withValues(alpha: 0.13),
                ),
                child: IconTheme(
                  data: IconThemeData(color: world.fg, size: 22),
                  child: icon,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: world.fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The one loud button on a world: a full pill in the world's CTA colour.
class WorldButton extends StatelessWidget {
  const WorldButton({
    super.key,
    required this.world,
    required this.label,
    required this.onPressed,
    this.iconWidget,
  });

  final AppWorld world;
  final String label;
  final VoidCallback? onPressed;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final fg = world.onCta;
    return Pressable(
      enabled: onPressed != null,
      scale: 0.96,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: world.cta,
          foregroundColor: fg,
          overlayColor: fg.withValues(alpha: 0.08),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                Haptics.press();
                onPressed!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconWidget != null) ...[
                IconTheme.merge(
                  data: IconThemeData(color: fg, size: 21),
                  child: iconWidget!,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the status bar painted in the tab's world colour while the page
/// scrolls, so content never slides under the clock and the status-bar
/// icons keep the right contrast after the [WorldHeader] has left.
class WorldStatusBar extends StatelessWidget {
  const WorldStatusBar({super.key, required this.world, required this.child});

  final AppWorld world;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (world.isDarkBg
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(statusBarColor: Colors.transparent),
              child: ColoredBox(color: world.paint),
            ),
          ),
        ),
      ],
    );
  }
}

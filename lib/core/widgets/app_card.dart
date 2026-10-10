import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpace.xl),
    this.color,
    this.radius = AppRadius.card,
    this.border,
    this.shadow = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Defaults to [AppColors.surface].
  final Color? color;
  final double radius;
  final BoxBorder? border;
  final bool shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: br,
        border: border ?? Border.all(color: AppColors.border),
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap != null) {
      card = Pressable(onTap: onTap, scale: 0.975, child: card);
    }
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      container: semanticLabel != null,
      child: card,
    );
  }
}

/// One white card holding rows separated by hairline dividers – the
/// "grouped list" used for settings, details and activity.
class CardGroup extends StatelessWidget {
  const CardGroup({
    super.key,
    required this.children,
    this.indent = 16,
    this.padding = EdgeInsets.zero,
  });
  final List<Widget> children;
  final double indent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: padding,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, indent: indent),
          children[i],
        ],
      ],
    ),
  );
}

/// Section heading – quiet, sentence case ("Needs your attention").
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 32, 2, 12),
  });
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Small rounded pill (status / tags).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.color,
    this.background,
    this.icon,
    this.dense = false,
  });
  final String label;

  /// Text colour; defaults to [AppColors.inkSoft].
  final Color? color;
  final Color? background;
  final Widget? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.inkSoft;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color:
            background ?? fg.withValues(alpha: AppColors.isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 5)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status dot + text, never colour alone. Pulses while something is live.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.pulse = true,
  });
  final String label;

  /// Dot colour; defaults to [AppColors.success]. Also the text colour
  /// unless [textColor] is given.
  final Color? color;
  final Color? textColor;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pulse(color: c, enabled: pulse),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: textColor ?? c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.enabled});
  final Color color;
  final bool enabled;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool _live(BuildContext context) =>
      widget.enabled && !AppMotion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (_live(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    height: 14,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8 + 6 * _c.value,
            height: 8 + 6 * _c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(
                alpha: _c.isAnimating ? 0.35 * (1 - _c.value) : 0,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The signature CTA: a solid marigold button with dark text, a spring
/// squish on press and a light haptic. One per screen – it marks "the thing
/// to do next". Label ⇄ spinner crossfade while [loading].
///
/// Labels wrap to two lines rather than shrinking, so large font settings
/// stay large.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.loading = false,
    this.color,
    this.trailingArrow = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A custom glyph (e.g. an [AppGlyph]) instead of [icon].
  final Widget? iconWidget;
  final bool loading;

  /// Fill colour for special cases (WhatsApp, danger) – always carries white
  /// text. Defaults to the signature [AppColors.accent] with dark text.
  final Color? color;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onPressed != null;
    final fill = color ?? AppColors.accent;
    final fg = color == null ? AppColors.onAccent : Colors.white;
    final br = BorderRadius.circular(AppRadius.button);
    return Pressable(
      enabled: enabled,
      scale: 0.96,
      child: ClipRRect(
        borderRadius: br,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: fg,
            shadowColor: Colors.transparent,
            overlayColor: fg.withValues(alpha: 0.08),
          ),
          onPressed: enabled
              ? () {
                  Haptics.press();
                  onPressed!();
                }
              : null,
          child: SwapFade(
            duration: AppMotion.fast,
            child: loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: fg,
                    ),
                  )
                : Padding(
                    key: const ValueKey('label'),
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
                        ] else if (icon != null) ...[
                          Icon(icon, size: 21),
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
                        if (trailingArrow) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Pressable(
    enabled: onPressed != null,
    scale: 0.97,
    child: OutlinedButton(
      onPressed: onPressed == null
          ? null
          : () {
              Haptics.tap();
              onPressed!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
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

/// Rounded-square icon bubble used inside cards.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.child,
    this.color,
    this.size = 48,
  });
  final Widget child;

  /// Defaults to [AppColors.brandSoft].
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color ?? AppColors.brandSoft,
      borderRadius: BorderRadius.circular(size * 0.36),
    ),
    child: child,
  );
}

/// Renders the line icon mapped to [e] (see [AppIcons]); falls back to the
/// emoji glyph only when no icon exists (e.g. unexpected backend titles).
class Emoji extends StatelessWidget {
  const Emoji(this.e, {super.key, this.size = 22, this.color});
  final String e;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final icon = AppIcons.forEmoji(e);
    return ExcludeSemantics(
      child: icon != null
          ? Icon(icon, size: size, color: color ?? AppColors.ink)
          : Text(e, style: TextStyle(fontSize: size, height: 1.1)),
    );
  }
}

/// Filter pill: fills with ink when selected (colours crossfade, the new
/// selection pops). The hit area is 44 px tall even though the pill is 36.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.iconColor,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final Color? iconColor;

  /// Optional number shown after the label.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final dur = AppMotion.of(context, AppMotion.base);
    final fg = selected ? AppColors.onInverse : AppColors.inkSoft;
    return Semantics(
      selected: selected,
      button: true,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: Pressable(
        onTap: selected ? () {} : onSelected,
        haptic: !selected,
        scale: 0.93,
        // At least 44 high (easy to hit), and taller with large text.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: AnimatedContainer(
              duration: dur,
              curve: AppMotion.standard,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.inverse : AppColors.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: selected ? AppColors.inverse : AppColors.border,
                  width: 1.2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.inverse.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: selected ? fg : (iconColor ?? fg),
                    ),
                    const SizedBox(width: 5),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: dur,
                    style:
                        (Theme.of(context).textTheme.labelMedium ??
                                const TextStyle())
                            .copyWith(color: fg, fontSize: 14),
                    child: Text(label),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: dur,
                      style:
                          (Theme.of(context).textTheme.labelMedium ??
                                  const TextStyle())
                              .copyWith(
                                color: fg.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                      child: Text('$count'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of [AppFilterChip]s with page padding.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    // Grows with the text size so chip labels are never clipped.
    height:
        56 +
        ((MediaQuery.textScalerOf(context).scale(14) - 14) * 1.4).clamp(
          0.0,
          double.infinity,
        ),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.page,
        vertical: 6,
      ),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => children[i],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpace.xl),
    this.color = AppColors.surface,
    this.radius = AppRadius.card,
    this.border,
    this.shadow = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final BoxBorder? border;
  final bool shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(
        borderRadius: br,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: content,
      );
    }
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: br, border: border, boxShadow: shadow ? AppShadows.card : null),
        child: Material(type: MaterialType.transparency, borderRadius: br, clipBehavior: Clip.antiAlias, child: content),
      ),
    );
  }
}

/// Uppercase section label – "TODAY'S RESULTS".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 28, 4, 12)});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Small rounded pill (status / tags).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color = AppColors.inkSoft, this.background, this.icon, this.dense = false});
  final String label;
  final Color color;
  final Color? background;
  final Widget? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
    decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 5)],
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color, fontSize: dense ? 11.5 : 12.5, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

/// Status dot + text, never colour alone.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.label, this.color = AppColors.success, this.pulse = true});
  final String label;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Pulse(color: color, enabled: pulse),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.enabled});
  final Color color;
  final bool enabled;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat();
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
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          if (widget.enabled)
            Container(
              width: 8 + 6 * _c.value,
              height: 8 + 6 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ],
      ),
    ),
  );
}

/// Big CTA button with optional leading emoji/icon and loading state.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
    this.trailingArrow = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color? color;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      onPressed: loading || onPressed == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onPressed!();
            },
      child: loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 21), const SizedBox(width: 8)],
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
                ),
                if (trailingArrow) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 20)],
              ],
            ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onPressed!();
          },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
        ),
      ],
    ),
  );
}

/// Round icon bubble used inside cards.
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.child, this.color = AppColors.brandSoft, this.size = 48});
  final Widget child;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.36)),
    child: child,
  );
}

class Emoji extends StatelessWidget {
  const Emoji(this.e, {super.key, this.size = 22});
  final String e;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(e, style: TextStyle(fontSize: size, height: 1.1)),
  );
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A tone is a colour pair used by pills, icon tiles and stat cards.
class Tone {
  const Tone(this.foreground, this.background);

  final Color foreground;
  final Color background;

  static const green = Tone(Color(0xFF0E8A54), AppColors.brandSoft);
  static const blue = Tone(Color(0xFF2A55D6), AppColors.blueSoft);
  static const purple = Tone(Color(0xFF6D3BEF), AppColors.purpleSoft);
  static const amber = Tone(AppColors.amberInk, AppColors.amberSoft);
  static const coral = Tone(Color(0xFFD6453F), AppColors.coralSoft);
  static const neutral = Tone(AppColors.inkSoft, AppColors.secondary);
}

/// A compact status chip.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.large = false,
  });

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 10, vertical: large ? 7 : 5),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: large ? 14 : 12, color: tone.foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppText.label.copyWith(
              color: tone.foreground,
              fontSize: large ? 12 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded white card with the app's soft shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.radius = AppRadius.xxl,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: kCardShadow,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// A section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.title)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A circular avatar showing the customer's initials on their colour.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.initials,
    required this.colorHex,
    this.size = 44,
  });

  final String initials;
  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colorFromHex(colorHex), shape: BoxShape.circle),
      child: Text(
        initials,
        style: AppText.caption.copyWith(
          color: Colors.white,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Parses a `#RRGGBB` string from the backend into a [Color].
Color colorFromHex(String hex) {
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.tryParse(value, radix: 16) ?? 0xFF18C97A);
}

/// A friendly mascot: the visual stand-in for our AI employee.
///
/// Drawn with plain shapes so the app ships with no binary image assets.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 64, this.mood = MascotMood.happy, this.animate = true});

  final double size;
  final MascotMood mood;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final background = switch (mood) {
      MascotMood.calling => AppColors.blueSoft,
      MascotMood.confused => AppColors.amberSoft,
      MascotMood.celebrating => AppColors.brandSoft,
      MascotMood.happy => AppColors.purpleSoft,
    };
    final accent = switch (mood) {
      MascotMood.calling => AppColors.blue,
      MascotMood.confused => AppColors.amberInk,
      MascotMood.celebrating => AppColors.brand,
      MascotMood.happy => AppColors.purple,
    };

    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: accent.withOpacity(0.28), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.30,
            child: Row(
              children: [
                _Eye(size: size * 0.11, color: accent),
                SizedBox(width: size * 0.16),
                _Eye(size: size * 0.11, color: accent),
              ],
            ),
          ),
          Positioned(
            top: size * 0.55,
            child: Container(
              width: size * 0.28,
              height: size * 0.14,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(size * 0.14),
                  top: Radius.circular(size * 0.04),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!animate) return face;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(scale: 0.8 + value * 0.2, child: child),
      child: face,
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

enum MascotMood { happy, calling, confused, celebrating }

/// A soft coloured tile used to lead a settings row or a stat.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.tone = Tone.green, this.size = 40});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.foreground),
    );
  }
}

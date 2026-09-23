import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// Primary brand button, tall enough to be an easy tap target.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.dark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final background = dark ? AppColors.ink : AppColors.brand;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 19, color: Colors.white),
                        const SizedBox(width: 9),
                      ],
                      Text(
                        label,
                        style: AppText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Quieter button used for secondary actions and inline choices.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = Tone.neutral,
    this.selected = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Tone tone;
  final bool selected;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final background = selected ? tone.background : AppColors.surface;
    final border = selected ? tone.foreground.withOpacity(0.35) : AppColors.border;

    final content = Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: border, width: selected ? 1.6 : 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: tone.foreground),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onPressed,
        child: expand ? SizedBox(width: double.infinity, child: content) : content,
      ),
    );
  }
}

/// Round icon button, used for the live-call controls.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.tone = Tone.neutral,
    this.size = 52,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: tone.background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: tone.foreground, size: size * 0.42),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(label!, style: AppText.label.copyWith(color: AppColors.inkSoft)),
        ],
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// "Continue with Google" per Google's sign-in branding: light or dark
/// neutral surface, neutral border, the four-colour G on the left.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label,
  });

  final VoidCallback? onPressed;
  final bool loading;

  /// Defaults to "Continue with Google" in the app language.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? context.s.continueWithGoogle;
    final enabled = onPressed != null && !loading;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Google's published button colours for each theme.
    final fill = dark ? const Color(0xFF131314) : Colors.white;
    final stroke = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);
    final ink = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled
            ? () {
                Haptics.press();
                onPressed!();
              }
            : null,
        haptic: false,
        scale: 0.97,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.base),
          height: 56,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: stroke, width: 1),
            boxShadow: enabled && !dark ? AppShadows.card : const [],
          ),
          child: SwapFade(
            duration: AppMotion.fast,
            child: loading
                ? Center(
                    key: const ValueKey('loading'),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: ink,
                      ),
                    ),
                  )
                : Padding(
                    key: const ValueKey('label'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const GoogleG(size: 20),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The Google "G", painted (no image asset).
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GPainter());
}

class _GPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: (s - stroke) / 2,
    );
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;

    canvas.drawArc(rect, deg(-40), deg(-100), false, arc(_red));
    canvas.drawArc(rect, deg(-140), deg(-90), false, arc(_yellow));
    canvas.drawArc(rect, deg(-230), deg(-95), false, arc(_green));
    canvas.drawArc(rect, deg(-325), deg(-35), false, arc(_blue));
    // The crossbar.
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke / 4, stroke),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thin divider with a centered label ("or").
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label});

  /// Defaults to "or" in the app language.
  final String? label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Divider(color: AppColors.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label ?? context.s.orLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      Expanded(child: Divider(color: AppColors.border)),
    ],
  );
}

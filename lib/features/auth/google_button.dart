import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// "Continue with Google" per Google's sign-in branding: white surface,
/// neutral border, the four-colour G on the left.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = 'Continue with Google',
  });

  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: const Color(0xFFDADCE0), width: 1.2),
            boxShadow: enabled ? AppShadows.card : const [],
          ),
          child: SwapFade(
            duration: AppMotion.fast,
            child: loading
                ? const Center(
                    key: ValueKey('loading'),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const GoogleG(size: 20),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF1F1F1F),
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
  const OrDivider({super.key, this.label = 'or'});
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: AppColors.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      const Expanded(child: Divider(color: AppColors.border)),
    ],
  );
}

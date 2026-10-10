import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../l10n/l10n.dart';

/// Circular call control (mute / end) with a label underneath.
///
/// Every control reserves the same [slot] height for its circle, so labels
/// line up across controls of different sizes.
class VoiceRoundControl extends StatelessWidget {
  const VoiceRoundControl({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
    this.size = 64,
    this.slot = 76,
    this.bordered = false,
  });
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final double size;
  final double slot;
  final bool bordered;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: slot,
          child: Center(
            child: AnimatedOpacity(
              duration: AppMotion.of(context, AppMotion.base),
              opacity: onTap == null ? 0.4 : 1,
              child: Pressable(
                enabled: onTap != null,
                scale: 0.9,
                child: Material(
                  color: background,
                  shape: CircleBorder(
                    side: bordered
                        ? BorderSide(color: AppColors.border, width: 1.2)
                        : BorderSide.none,
                  ),
                  elevation: 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap == null
                        ? null
                        : () {
                            Haptics.press();
                            onTap!();
                          },
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: PopSwitcher(
                        child: Icon(
                          icon,
                          key: ValueKey(icon),
                          color: foreground,
                          size: size * 0.42,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ],
    ),
  );
}

/// Shown in place of the transcript when the voice session fails.
class VoiceErrorPanel extends StatelessWidget {
  const VoiceErrorPanel({
    super.key,
    required this.message,
    required this.permissionDenied,
    required this.onRetry,
    this.onContinue,
    this.fromOnboarding = false,
  });
  final String message;
  final bool permissionDenied;
  final VoidCallback onRetry;
  final VoidCallback? onContinue;
  final bool fromOnboarding;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              child: Icon(
                permissionDenied
                    ? Icons.mic_off_rounded
                    : Icons.wifi_off_rounded,
                size: 36,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: 12),
            Text(message, style: t.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: 240,
              child: permissionDenied
                  ? PrimaryButton(
                      label: s.openSettings,
                      onPressed: openAppSettings,
                    )
                  : PrimaryButton(label: s.tryAgain, onPressed: onRetry),
            ),
            if (onContinue != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 240,
                child: SecondaryButton(
                  label: fromOnboarding ? s.continueToDashboard : s.goBack,
                  onPressed: onContinue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lightweight animated bars driven by audio level.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({super.key, required this.level, required this.color});
  final double level;
  final Color color;
  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: const Size(220, 44),
            painter: _WavePainter(
              phase: _c.value,
              level: widget.level,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.phase, required this.level, required this.color});
  final double phase;
  final double level;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const bars = 21;
    final w = size.width / (bars * 1.8);
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final center = 1 - ((i - bars / 2).abs() / (bars / 2));
      final wave = (math.sin((phase * 2 * math.pi) + i * 0.7) + 1) / 2;
      final h =
          4 +
          (size.height - 8) *
              (0.08 + level * (0.35 + 0.65 * wave) * (0.4 + 0.6 * center));
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.phase != phase || o.level != level || o.color != color;
}

/// Tappable canned question the owner can send to their AI employee.
class VoiceSuggestionChip extends StatelessWidget {
  const VoiceSuggestionChip({
    super.key,
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.94,
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
        onPressed: () {
          Haptics.tap();
          onTap();
        },
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';

/// Circular call control (mute / end) with a label underneath.
class VoiceRoundControl extends StatelessWidget {
  const VoiceRoundControl({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
    this.size = 64,
  });
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: foreground, size: size * 0.42),
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
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: t.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: permissionDenied
                  ? PrimaryButton(
                      label: 'Open settings',
                      onPressed: openAppSettings,
                    )
                  : PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
            if (onContinue != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 220,
                child: SecondaryButton(
                  label: fromOnboarding ? 'Continue to dashboard' : 'Go back',
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
  )..repeat();
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
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

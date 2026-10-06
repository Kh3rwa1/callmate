import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_colors.dart';

class TempStyle {
  const TempStyle(this.fg, this.bg, this.emoji, this.label);
  final Color fg;
  final Color bg;
  final String emoji;
  final String label;

  static TempStyle of(LeadTemperature t) => switch (t) {
    LeadTemperature.hot => const TempStyle(AppColors.hot, AppColors.hotSoft, '🔥', 'HOT'),
    LeadTemperature.warm => const TempStyle(Color(0xFFB45309), AppColors.warmSoft, '☀️', 'WARM'),
    LeadTemperature.cold => const TempStyle(AppColors.cold, AppColors.coldSoft, '❄️', 'COLD'),
    LeadTemperature.unknown => const TempStyle(AppColors.inkFaint, AppColors.surfaceMuted, '•', 'NEW'),
  };
}

/// "🔥 87 — HOT" badge (emoji + number + word: never colour alone).
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.large = false});
  final LeadScore? score;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = score?.temperature ?? LeadTemperature.unknown;
    final s = TempStyle.of(t);
    final text = score == null ? 'Not called yet' : '${score!.value} — ${s.label}';
    return Semantics(
      label: score == null ? 'Not scored yet' : 'Lead score ${score!.value}, ${s.label.toLowerCase()}',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 8 : 5),
          decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (score != null) Text(s.emoji, style: TextStyle(fontSize: large ? 16 : 13)),
              if (score != null) const SizedBox(width: 5),
              Text(
                text,
                style: TextStyle(color: s.fg, fontWeight: FontWeight.w800, fontSize: large ? 15 : 12.5, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated circular score gauge for the post-call screen.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 132});
  final LeadScore score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = TempStyle.of(score.temperature);
    return Semantics(
      label: 'Lead score ${score.value} out of 100',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: score.value / 100),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(value: v, strokeWidth: 11, strokeCap: StrokeCap.round, backgroundColor: s.bg, color: s.fg),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 20)),
                  Text('${(v * 100).round()}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 36, height: 1)),
                  Text('/ 100', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initials avatar coloured by temperature.
class LeadAvatar extends StatelessWidget {
  const LeadAvatar({super.key, required this.name, this.temperature = LeadTemperature.unknown, this.size = 46});
  final String name;
  final LeadTemperature temperature;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = (parts.first.isNotEmpty ? parts.first[0] : '?') + (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '');
    final s = TempStyle.of(temperature);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: s.bg, shape: BoxShape.circle),
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: s.fg == AppColors.inkFaint ? AppColors.inkSoft : s.fg,
            fontSize: size * 0.34,
          ),
        ),
      ),
    );
  }
}

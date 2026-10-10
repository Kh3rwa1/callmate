import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import 'app_card.dart';

/// Colours and icon for a lead temperature (labels come from [SCommon]).
class TempStyle {
  const TempStyle(this.fg, this.bg, this.icon);
  final Color fg;
  final Color bg;
  final IconData icon;

  static TempStyle of(LeadTemperature t) => switch (t) {
    LeadTemperature.hot => TempStyle(
      AppColors.hot,
      AppColors.hotSoft,
      Icons.local_fire_department_rounded,
    ),
    LeadTemperature.warm => TempStyle(
      AppColors.warmInk,
      AppColors.warmSoft,
      Icons.wb_sunny_rounded,
    ),
    LeadTemperature.cold => TempStyle(
      AppColors.cold,
      AppColors.coldSoft,
      Icons.ac_unit_rounded,
    ),
    LeadTemperature.unknown => TempStyle(
      AppColors.inkFaint,
      AppColors.surfaceMuted,
      Icons.fiber_new_rounded,
    ),
  };
}

/// "🔥 Wants to buy" badge (icon + plain words: never colour alone, never a
/// bare number). [showNumber] adds the score for screens that explain it.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({
    super.key,
    required this.score,
    this.large = false,
    this.showNumber = false,
  });
  final LeadScore? score;
  final bool large;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = score?.temperature ?? LeadTemperature.unknown;
    final style = TempStyle.of(t);
    final word = s.temperature(t);
    final text = score == null
        ? s.notScoredYet
        : showNumber
        ? '$word · ${score!.value}'
        : word;
    return Semantics(
      label: score == null
          ? s.notScoredYet
          : showNumber
          ? s.pick(
              '$word, score ${score!.value} out of 100',
              '$word, 100 में से ${score!.value}',
              '$word, 100-এর মধ্যে ${score!.value}',
            )
          : word,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          // Words are longer than "87 · Hot"; cap the width so a long
          // translation ellipsizes instead of pushing the row over.
          constraints: BoxConstraints(maxWidth: large ? 260 : 156),
          duration: AppMotion.of(context, AppMotion.base),
          padding: EdgeInsets.symmetric(
            horizontal: large ? 14 : 10,
            vertical: large ? 8 : 5,
          ),
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (score != null) ...[
                Icon(style.icon, size: large ? 17 : 14, color: style.fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.fg,
                    fontWeight: FontWeight.w600,
                    fontSize: large ? 15 : 13,
                    letterSpacing: 0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated circular score gauge for the post-call screen: the arc sweeps
/// while the number counts up, then the ring gives a small settle pulse.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 132});
  final LeadScore score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TempStyle.of(score.temperature);
    final s = context.s;
    return Semantics(
      label: s.pick(
        'Buying chance ${score.value} out of 100',
        'खरीदने की संभावना 100 में से ${score.value}',
        'কেনার সম্ভাবনা 100-এর মধ্যে ${score.value}',
      ),
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: score.value / 100),
          duration: AppMotion.of(context, const Duration(milliseconds: 1200)),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) {
            final done = v >= score.value / 100 - 0.001;
            return SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: v,
                      strokeWidth: 11,
                      strokeCap: StrokeCap.round,
                      backgroundColor: style.bg,
                      color: style.fg,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: done ? 1 : 0.8,
                        duration: AppMotion.of(context, AppMotion.slow),
                        curve: AppMotion.pop,
                        child: Icon(style.icon, size: 22, color: style.fg),
                      ),
                      Text(
                        '${(v * 100).round()}',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontSize: 36,
                              height: 1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      Text(
                        '/ 100',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Initials avatar coloured by temperature.
class LeadAvatar extends StatelessWidget {
  const LeadAvatar({
    super.key,
    required this.name,
    this.temperature = LeadTemperature.unknown,
    this.size = 46,
  });
  final String name;
  final LeadTemperature temperature;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first.characters;
    final last = parts.length > 1 ? parts.last.characters : null;
    final initials =
        (first.isNotEmpty ? first.first : '?') +
        (last != null && last.isNotEmpty ? last.first : '');
    final style = TempStyle.of(temperature);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.base),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: style.bg, shape: BoxShape.circle),
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: temperature == LeadTemperature.unknown
                ? AppColors.inkSoft
                : style.fg,
            fontSize: size * 0.34,
          ),
        ),
      ),
    );
  }
}

/// "Form" / "Website" / "Google Ads" / "IndiaMART" / "Facebook" chip for leads
/// that arrived by themselves through the enquiry form, a website webhook or a
/// lead-source integration. Nothing for leads added by hand.
class LeadSourceChip extends StatelessWidget {
  const LeadSourceChip({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final label = context.s.leadSourceLabel(source);
    if (label == null) return const SizedBox.shrink();
    return Pill(
      label: label,
      dense: true,
      color: AppColors.info,
      icon: Icon(
        switch (source) {
          'form' => Icons.dynamic_form_outlined,
          'google_ads' => Icons.campaign_outlined,
          'indiamart' => Icons.storefront_outlined,
          'meta' => Icons.thumb_up_alt_outlined,
          _ => Icons.language_rounded,
        },
        size: 12,
        color: AppColors.info,
      ),
    );
  }
}

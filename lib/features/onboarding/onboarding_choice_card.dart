import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';

/// Selectable card used by the business-type and skills steps.
class OnboardingChoiceCard extends StatelessWidget {
  const OnboardingChoiceCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multi = false,
  });
  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.cardSm),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.cardSm),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Emoji(
                          emoji,
                          size: 21,
                          color: selected ? AppColors.brand : AppColors.ink,
                        ),
                      ),
                      const Spacer(),
                      if (selected)
                        Icon(
                          multi
                              ? Icons.check_box_rounded
                              : Icons.check_circle_rounded,
                          color: AppColors.brand,
                        )
                      else if (multi)
                        const Icon(
                          Icons.check_box_outline_blank_rounded,
                          color: AppColors.border,
                          size: 22,
                        ),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title, style: t.titleSmall, maxLines: 1),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: t.bodySmall?.copyWith(
                        fontSize: 12,
                        color: AppColors.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

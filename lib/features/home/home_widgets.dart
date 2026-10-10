import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// "Needs your attention": a quiet, flat list (1 px border, no shadow) so
/// it sits below the hero and the weekly results in visual weight.
class HomeActionGroup extends StatelessWidget {
  const HomeActionGroup({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
    shadow: false,
    child: AnimatedSize(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60, endIndent: 16),
            rows[i],
          ],
        ],
      ),
    ),
  );
}

/// "[icon]  12 ready to buy  ›" – count bold, label soft, no sentences. An
/// optional [detail] line sits underneath (e.g. the next callback).
class HomeActionRow extends StatelessWidget {
  const HomeActionRow({
    super.key,
    required this.glyph,
    required this.color,
    required this.tint,
    required this.label,
    required this.onTap,
    this.count,
    this.trailing,
    this.detail,
  });
  final AppGlyphs glyph;
  final Color color;
  final Color tint;
  final int? count;
  final String label;
  final String? trailing;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final strong = t.bodyLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
    );
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: AppGlyph(glyph, size: 18, color: color),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (count != null)
                            TextSpan(
                              text: '${Fmt.number(count!)} ',
                              style: strong,
                            ),
                          TextSpan(
                            text: label,
                            style: count == null
                                ? strong?.copyWith(fontWeight: FontWeight.w500)
                                : t.bodyLarge?.copyWith(
                                    color: AppColors.inkSoft,
                                  ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpace.sm),
                  child: Text(
                    trailing!,
                    style: t.labelMedium?.copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact one-line timeline: icon · text · faint time.
class HomeActivityList extends StatelessWidget {
  const HomeActivityList({
    super.key,
    required this.items,
    required this.emptyText,
  });
  final List<ActivityItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return AppCard(
        shadow: false,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(emptyText, style: t.bodyMedium),
      );
    }
    return AppCard(
      shadow: false,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(
        children: [
          for (final a in items)
            InkWell(
              onTap: a.route == null ? null : () => context.go(a.route!),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg,
                    vertical: AppSpace.md,
                  ),
                  child: Row(
                    children: [
                      Emoji(a.emoji, size: 18, color: AppColors.inkSoft),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text(
                          a.text,
                          style: t.bodyMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Text(
                        s.relative(a.at),
                        style: t.bodySmall,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shimmering stand-in for Home while the summary loads, shaped like the
/// real page (funnel card, attention rows) so nothing jumps.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.s.loading,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: AppSpace.xxl),
        Skeleton(height: 18, width: 120),
        SizedBox(height: AppSpace.md),
        AppCard(
          padding: EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: 40, width: 150),
              SizedBox(height: AppSpace.lg),
              _BarBone(0.95),
              _BarBone(0.7),
              _BarBone(0.45),
              _BarBone(0.25),
            ],
          ),
        ),
        SizedBox(height: AppSpace.xxl),
        Skeleton(height: 18, width: 160),
        SizedBox(height: AppSpace.md),
        SkeletonCard(lines: 1),
      ],
    ),
  );
}

class _BarBone extends StatelessWidget {
  const _BarBone(this.fraction);
  final double fraction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: fraction,
      child: const Skeleton(height: 10, radius: 99),
    ),
  );
}

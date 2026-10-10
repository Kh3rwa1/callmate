import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/widgets/celebration.dart';
import '../../l10n/l10n.dart';

/// Bottom navigation: exactly Home · Customers · Calls · Messages ·
/// My employee.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _icons = [
    AppGlyphs.home,
    AppGlyphs.customers,
    AppGlyphs.call,
    AppGlyphs.message,
    AppGlyphs.employee,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final pending = ref.watch(dashboardProvider).value?.followUpsReady ?? 0;
    final labels = [
      s.navHome,
      s.navLeads,
      s.navCalls,
      s.navFollowUps,
      s.navAgent,
    ];
    return Scaffold(
      body: HotLeadCelebrator(child: shell),
      bottomNavigationBar: AppNavBar(
        index: shell.currentIndex,
        items: [
          for (var i = 0; i < _icons.length; i++)
            NavItemData(_icons[i], labels[i]),
        ],
        badges: {3: pending},
        onSelect: (i) {
          Haptics.tap();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
      ),
    );
  }
}

class NavItemData {
  const NavItemData(this.glyph, this.label);
  final AppGlyphs glyph;
  final String label;
}

/// The tab bar: CallPilot's own rounded icons, a pill that glides (with a
/// slight overshoot) behind the selected tab, labels at 12.5+ that wrap
/// rather than truncate, and badges that pop when their count changes.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.index,
    required this.items,
    required this.onSelect,
    this.badges = const {},
  });
  final int index;
  final List<NavItemData> items;
  final ValueChanged<int> onSelect;
  final Map<int, int> badges;

  static const _pillWidth = 60.0;
  static const _pillHeight = 32.0;

  /// Tab labels stop growing here so five tabs still fit side by side.
  static const _maxLabelScale = 1.3;
  static const labelFontSize = 12.5;

  /// The text scaler for tab labels.
  static TextScaler labelScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _maxLabelScale);

  /// Height of one line of tab label.
  static double labelLine(BuildContext context) =>
      labelScaler(context).scale(labelFontSize) * 1.25;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        // One line per label, never split inside a word: labels grow with
        // the owner's text size up to [_maxLabelScale] and shrink to fit
        // their tab if a long word ("मेरा कर्मचारी") would not fit.
        child: SizedBox(
          height: 32 + 4 + 14 + labelLine(context),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 460),
                    curve: const Cubic(0.3, 1.3, 0.45, 1),
                    left: w * index + (w - _pillWidth) / 2,
                    top: 7,
                    width: _pillWidth,
                    height: _pillHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavItem(
                            data: items[i],
                            selected: i == index,
                            badge: badges[i],
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final NavItemData data;
  final bool selected;

  /// null: this tab never shows a badge.
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final dur = AppMotion.of(context, AppMotion.base);
    final count = badge ?? 0;
    final icon = PopSwitcher(
      duration: AppMotion.slow,
      child: AppGlyph(
        data.glyph,
        key: ValueKey(selected),
        size: 24,
        color: selected ? AppColors.brand : AppColors.inkFaint,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: count > 0 ? s.navPending(data.label, count) : data.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptic: false,
        scale: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: badge == null
                    ? icon
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          icon,
                          Positioned(
                            right: -10,
                            top: -6,
                            child: PopSwitcher(
                              child: count == 0
                                  ? const SizedBox.shrink(key: ValueKey(0))
                                  : _Badge(
                                      key: ValueKey(count),
                                      text: count > 99 ? '99+' : '$count',
                                    ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: dur,
              curve: AppMotion.standard,
              style: (t.labelSmall ?? const TextStyle()).copyWith(
                fontSize: AppNavBar.labelFontSize,
                height: 1.2,
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.inkFaint,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    data.label,
                    key: ValueKey('nav-label-${data.label}'),
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    textScaler: AppNavBar.labelScaler(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.hotFill,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.surface, width: 1.5),
    ),
    child: Text(
      text,
      textScaler: TextScaler.noScaling,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.1,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

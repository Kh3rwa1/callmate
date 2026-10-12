import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
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

/// The tab bar: a floating paper capsule with CallPilot's own rounded
/// icons. The selected tab sits in a pill painted in that tab's colour
/// world (cobalt, ink, tomato, chartreuse, marigold) that glides between
/// tabs. Labels stay at 12.5+ and never truncate; badges pop when their
/// count changes.
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

  /// Height of the capsule. Icons only: every screen already shows its
  /// name in big letters at the top, so words here would just repeat it.
  static const barHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final world = AppWorld.ofTab(index);
    final dur = reduced ? Duration.zero : const Duration(milliseconds: 420);
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Container(
            height: barHeight,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.raised,
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: dur,
                      curve: const Cubic(0.3, 1.15, 0.45, 1),
                      left: w * index,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: AnimatedContainer(
                        duration: dur,
                        curve: AppMotion.standard,
                        decoration: BoxDecoration(
                          color: world.paint,
                          borderRadius: BorderRadius.circular(25),
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
                              selectedColor: world.fg,
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
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.selectedColor,
    required this.badge,
    required this.onTap,
  });
  final NavItemData data;
  final bool selected;
  final Color selectedColor;

  /// null: this tab never shows a badge.
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final count = badge ?? 0;
    final fg = selected ? selectedColor : AppColors.inkFaint;
    final icon = PopSwitcher(
      duration: AppMotion.slow,
      child: AppGlyph(
        data.glyph,
        key: ValueKey('$selected-$fg'),
        size: 27,
        color: fg,
      ),
    );
    return Tooltip(
      // Long-press says the name, for anyone unsure what an icon means.
      message: data.label,
      excludeFromSemantics: true,
      child: Semantics(
        selected: selected,
        button: true,
        label: count > 0 ? s.navPending(data.label, count) : data.label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          haptic: false,
          scale: 0.9,
          child: Center(
            child: badge == null
                ? icon
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      icon,
                      Positioned(
                        right: -11,
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

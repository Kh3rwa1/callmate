import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';

/// Bottom navigation: exactly Home · Leads · Calls · Follow-ups · Agent.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _icons = [
    (Icons.home_outlined, Icons.home_rounded),
    (Icons.people_outline_rounded, Icons.people_rounded),
    (Icons.call_outlined, Icons.call_rounded),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
    (Icons.support_agent_outlined, Icons.support_agent_rounded),
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
      body: shell,
      bottomNavigationBar: AppNavBar(
        index: shell.currentIndex,
        items: [
          for (var i = 0; i < _icons.length; i++)
            NavItemData(_icons[i].$1, _icons[i].$2, labels[i]),
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
  const NavItemData(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The tab bar. A soft pill glides (with a slight overshoot) to the selected
/// tab; the icon fills in with a pop; badges pop when their count changes.
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
        child: SizedBox(
          height: 66,
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
      child: Icon(
        selected ? data.selectedIcon : data.icon,
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
                fontSize: 11.5,
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.brand : AppColors.inkFaint,
              ),
              child: Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.1,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

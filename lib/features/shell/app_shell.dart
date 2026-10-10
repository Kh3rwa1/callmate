import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

/// Bottom navigation: exactly Home · Leads · Calls · Follow-ups · Agent.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.people_outline_rounded, Icons.people_rounded, 'Leads'),
    (Icons.call_outlined, Icons.call_rounded, 'Calls'),
    (
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
      'Follow-ups',
    ),
    (Icons.support_agent_outlined, Icons.support_agent_rounded, 'Agent'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(dashboardProvider).value?.followUpsReady ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: AppNavBar(
        index: shell.currentIndex,
        badges: {3: pending},
        onSelect: (i) {
          Haptics.tap();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
      ),
    );
  }
}

class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.badges = const {},
  });
  final int index;
  final ValueChanged<int> onSelect;
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final tabs = AppShell._tabs;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: tabs[i].$1,
                    selectedIcon: tabs[i].$2,
                    label: tabs[i].$3,
                    selected: i == index,
                    badge: badges[i],
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;

  /// null: this tab never shows a badge.
  final int? badge;
  final VoidCallback onTap;

  Widget _icon() => SwapFade(
    duration: AppMotion.fast,
    child: Icon(
      selected ? selectedIcon : icon,
      key: ValueKey(selected),
      size: 24,
      color: selected ? AppColors.ink : AppColors.inkFaint,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dur = AppMotion.of(context, AppMotion.base);
    return Semantics(
      selected: selected,
      button: true,
      label: (badge ?? 0) > 0 ? '$label, $badge pending' : label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptic: false,
        scale: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 28,
              child: Center(
                child: badge == null
                    ? _icon()
                    : Badge(
                        isLabelVisible: badge! > 0,
                        backgroundColor: AppColors.hot,
                        largeSize: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        offset: const Offset(8, -5),
                        textStyle: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                        label: Text(badge! > 99 ? '99+' : '$badge'),
                        child: _icon(),
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
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.inkFaint,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
            ),
          ],
        ),
      ),
    );
  }
}

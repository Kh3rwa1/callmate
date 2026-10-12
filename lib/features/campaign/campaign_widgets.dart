import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../l10n/l10n.dart';

/// "Call New Leads" CTA. Full-width button on Home; [compact] is a small
/// pill for headers (Leads).
class CallNewLeadsButton extends StatelessWidget {
  const CallNewLeadsButton({
    super.key,
    required this.count,
    this.compact = false,
    this.background,
    this.foreground,
  });
  final int count;
  final bool compact;

  /// Compact pill colours (e.g. a world's CTA); default ink.
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (compact) {
      return Semantics(
        button: true,
        label: s.callNewSemantics(count),
        excludeSemantics: true,
        child: Pressable(
          onTap: () => context.push('/campaign/new'),
          scale: 0.94,
          child: Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
            decoration: BoxDecoration(
              color: background ?? AppColors.inverse,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone_forwarded_rounded,
                  size: 17,
                  color: foreground ?? AppColors.onInverse,
                ),
                const SizedBox(width: 7),
                Text(
                  s.callNewCompact(count),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground ?? AppColors.onInverse,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PrimaryButton(
      label: s.callNewLeadsCount(count),
      icon: Icons.phone_forwarded_rounded,
      onPressed: () => context.push('/campaign/new'),
    );
  }
}

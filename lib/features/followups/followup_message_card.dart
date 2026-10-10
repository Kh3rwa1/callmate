import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// WhatsApp-style message bubble. It rises in once, and its border glows
/// green while being edited.
class FollowUpMessageCard extends StatelessWidget {
  const FollowUpMessageCard({
    super.key,
    required this.controller,
    required this.editing,
    required this.onTapToEdit,
  });
  final TextEditingController controller;
  final bool editing;
  final VoidCallback onTapToEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Reveal(
      offset: 18,
      duration: const Duration(milliseconds: 560),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: AppColors.bubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
          border: Border.all(
            color: editing ? AppColors.whatsapp : AppColors.bubbleBorder,
            width: editing ? 2 : 1,
          ),
          boxShadow: editing
              ? AppShadows.glow(AppColors.whatsapp)
              : AppShadows.card,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.base),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: editing
                  ? TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: null,
                      minLines: 6,
                      style: t.bodyLarge,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  : Semantics(
                      button: true,
                      hint: s.tapToEdit,
                      child: GestureDetector(
                        onTap: onTapToEdit,
                        child: SizedBox(
                          width: double.infinity,
                          child: ValueListenableBuilder(
                            valueListenable: controller,
                            builder: (_, v, _) => Text(
                              v.text,
                              style: t.bodyLarge?.copyWith(height: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SwapFade(
                  child: Text(
                    editing ? s.editing : s.draft,
                    key: ValueKey(editing),
                    style: t.bodySmall?.copyWith(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_note_rounded,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

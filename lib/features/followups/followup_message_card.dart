import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// WhatsApp-style message bubble with gentle entrance animation.
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
    final t = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - v)),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE7F8DD),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
          border: Border.all(
            color: editing ? AppColors.whatsapp : const Color(0xFFCDEBC0),
            width: editing ? 2 : 1,
          ),
          boxShadow: AppShadows.card,
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            editing
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
                : GestureDetector(
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
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  editing ? 'Editing' : 'Draft',
                  style: t.bodySmall?.copyWith(fontSize: 11.5),
                ),
                const SizedBox(width: 4),
                const Icon(
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

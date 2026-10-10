import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import 'voice_test_status.dart';
import 'voice_test_widgets.dart';

/// Suggestion chips plus a free-text input for sending messages to the AI
/// employee during a live voice test.
class VoiceTestComposer extends StatelessWidget {
  const VoiceTestComposer({
    super.key,
    required this.controller,
    required this.employeeName,
    required this.onSend,
  });

  final TextEditingController controller;
  final String employeeName;

  /// Called with an explicit message (from a chip) or `null` to send the
  /// contents of [controller].
  final void Function([String? text]) onSend;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, (label, message)) in voiceTestSuggestions(
                s,
              ).indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                PopIn(
                  delay: Duration(milliseconds: 60 * i),
                  child: VoiceSuggestionChip(
                    label: label,
                    onTap: () => onSend(message),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: s.messageTo(employeeName),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: border(AppColors.border),
                  enabledBorder: border(AppColors.border),
                  focusedBorder: border(AppColors.brand, 1.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              scale: 0.88,
              child: IconButton.filled(
                tooltip: s.send,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.brandFill,
                  foregroundColor: Colors.white,
                  fixedSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: () => onSend(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

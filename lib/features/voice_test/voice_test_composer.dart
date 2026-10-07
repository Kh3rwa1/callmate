import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
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
              for (final (i, (label, message))
                  in voiceTestSuggestions.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                VoiceSuggestionChip(label: label, onTap: () => onSend(message)),
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
                  hintText: 'Talk or ask $employeeName anything…',
                  filled: true,
                  fillColor: Colors.white,
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
            IconButton.filled(
              icon: const Icon(Icons.send_rounded, size: 20),
              onPressed: () => onSend(),
            ),
          ],
        ),
      ],
    );
  }
}

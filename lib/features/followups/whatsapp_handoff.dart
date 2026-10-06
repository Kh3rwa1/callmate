import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import '../../services/whatsapp/whatsapp_service.dart';

/// Single place that performs the human-in-the-loop WhatsApp handoff.
/// Validates → opens WhatsApp → marks follow-up "opened" (never "sent").
Future<bool> openWhatsAppHandoff(
  BuildContext context,
  WidgetRef ref, {
  required String phone,
  required String message,
  FollowUp? followUp,
}) async {
  final wa = ref.read(whatsappServiceProvider);
  final result = await wa.openChat(phone: phone, message: message);
  if (!context.mounted) return false;

  switch (result) {
    case WhatsAppOpenResult.opened:
      HapticFeedback.mediumImpact();
      ref.read(analyticsProvider).track('whatsapp_opened', {'has_followup': followUp != null});
      if (followUp != null) {
        await ref
            .read(followUpRepoProvider)
            .update(followUp.copyWith(message: message, status: FollowUpStatus.opened, openedAt: DateTime.now()));
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('WhatsApp opened – tap Send there ✓')));
      }
      return true;
    case WhatsAppOpenResult.invalidPhone:
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('This phone number doesn\'t look right. Edit the lead and try again.')));
      return false;
    case WhatsAppOpenResult.emptyMessage:
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('The message is empty. Add some text first.')));
      return false;
    case WhatsAppOpenResult.notInstalled:
      await _fallback(context, wa, message);
      return false;
  }
}

Future<void> _fallback(BuildContext context, WhatsAppService wa, String message) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(state: MascotState.error, size: 110),
              const SizedBox(height: 10),
              Text('WhatsApp isn\'t installed', style: t.titleLarge),
              const SizedBox(height: 6),
              Text('Copy the message instead, or share it with another app.', style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Copy Message',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await wa.copyMessage(message);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
                  }
                },
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Share…',
                icon: Icons.ios_share_rounded,
                onPressed: () async {
                  Navigator.pop(ctx);
                  await wa.shareMessage(message);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The signature green "WhatsApp →" button.
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({super.key, required this.onPressed, this.label = 'WhatsApp', this.compact = false});
  final VoidCallback? onPressed;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.whatsapp,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.chat_rounded, size: 18),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      );
    }
    return Semantics(
      button: true,
      label: 'Open WhatsApp with the message ready to send',
      child: PrimaryButton(label: '$label →', icon: Icons.chat_rounded, color: AppColors.whatsapp, onPressed: onPressed),
    );
  }
}

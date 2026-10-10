import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
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
  final s = context.s;
  final wa = ref.read(whatsappServiceProvider);
  final result = await wa.openChat(phone: phone, message: message);
  if (!context.mounted) return false;

  switch (result) {
    case WhatsAppOpenResult.opened:
      Haptics.success();
      ref.read(analyticsProvider).track('whatsapp_opened', {
        'has_followup': followUp != null,
      });
      if (followUp != null) {
        await ref
            .read(followUpRepoProvider)
            .update(
              followUp.copyWith(
                message: message,
                status: FollowUpStatus.opened,
                openedAt: DateTime.now(),
              ),
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(s.waOpenedTapSend)));
      }
      return true;
    case WhatsAppOpenResult.invalidPhone:
      Haptics.warn();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.phoneLooksWrong)));
      return false;
    case WhatsAppOpenResult.emptyMessage:
      Haptics.warn();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.messageEmpty)));
      return false;
    case WhatsAppOpenResult.notInstalled:
      await _fallback(context, wa, message);
      return false;
  }
}

Future<void> _fallback(
  BuildContext context,
  WhatsAppService wa,
  String message,
) {
  final s = context.s;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            0,
            AppSpace.page,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(state: MascotState.error, size: 88),
              const SizedBox(height: 14),
              Text(s.waNotInstalled, style: t.titleLarge),
              const SizedBox(height: 6),
              Text(
                s.copyOrShareInstead,
                style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: s.copyMessage,
                icon: Icons.copy_rounded,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await wa.copyMessage(message);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    messenger.showSnackBar(
                      SnackBar(content: Text(s.messageCopied)),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: s.share,
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
  const WhatsAppButton({
    super.key,
    required this.onPressed,
    this.label = 'WhatsApp',
    this.compact = false,
  });
  final VoidCallback? onPressed;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Pressable(
        scale: 0.96,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.whatsappFill,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontFamilyFallback: AppTheme.fontFallback,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          onPressed: onPressed == null
              ? null
              : () {
                  Haptics.press();
                  onPressed!();
                },
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return Semantics(
      button: true,
      label: context.s.openWhatsappSemantics,
      child: PrimaryButton(
        label: '$label →',
        icon: Icons.chat_rounded,
        color: AppColors.whatsappFill,
        onPressed: onPressed,
      ),
    );
  }
}

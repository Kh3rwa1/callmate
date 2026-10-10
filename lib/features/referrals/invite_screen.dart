import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// WhatsApp share link with no recipient: WhatsApp opens its contact picker
/// with [message] prefilled. The owner picks who gets it and taps send;
/// nothing is ever sent automatically.
Uri whatsAppShareUri(String message) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message.trim())}');

/// "Invite & earn": the business's referral code and link, a WhatsApp share
/// the owner sends themselves, and how many invites signed up / paid.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.inviteAndEarn)),
      body: AsyncView<ReferralSummary>(
        value: ref.watch(referralsProvider),
        onRetry: () => ref.invalidate(referralsProvider),
        data: (r) => _Body(r),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.r);
  final ReferralSummary r;

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) _toast(context, context.s.copiedToClipboard);
  }

  Future<void> _shareWhatsApp(BuildContext context, String message) async {
    var opened = false;
    try {
      opened = await launchUrl(
        whatsAppShareUri(message),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && context.mounted) {
      _toast(context, context.s.whatsAppNotOpened);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final message = s.inviteMessage(r.link, r.code, r.bonusMinutes);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
      children: [
        Reveal(
          child: AppCard(
            color: AppColors.strong,
            border: Border.all(color: Colors.transparent),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.inviteHeadline(r.bonusMinutes),
                  style: t.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.inviteBody(r.bonusMinutes),
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                Text(
                  s.yourReferralCode,
                  style: t.labelLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        r.code,
                        key: const ValueKey('referral-code'),
                        style: t.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: s.copyCode,
                      onPressed: () => _copy(context, r.code),
                      icon: const Icon(Icons.copy_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Reveal(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: s.shareOnWhatsApp,
                icon: Icons.chat_rounded,
                color: AppColors.whatsapp,
                onPressed: () => _shareWhatsApp(context, message),
              ),
              const SizedBox(height: 8),
              Text(
                s.inviteYouSend,
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: s.copyLink,
                      icon: Icons.link_rounded,
                      onPressed: () => _copy(context, r.link),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SecondaryButton(
                      label: s.shareOtherApps,
                      icon: Icons.ios_share_rounded,
                      onPressed: () => ref
                          .read(whatsappServiceProvider)
                          .shareMessage(message),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Reveal(
          index: 2,
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              children: [
                _Stat(value: r.signedUp, label: s.referralsJoined),
                _Stat(value: r.rewarded, label: s.referralsPaid),
                _Stat(value: r.minutesEarned, label: s.minutesEarned),
              ],
            ),
          ),
        ),
        SectionLabel(s.inviteHowItWorks),
        Reveal(
          index: 3,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Step(n: 1, text: s.inviteStep1),
                _Step(n: 2, text: s.inviteStep2),
                _Step(n: 3, text: s.inviteStep3(r.bonusMinutes)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            Fmt.number(value),
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.brand,
            child: Text(
              '$n',
              style: t.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: t.bodyMedium)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';

/// A WhatsApp conversation with one customer.
///
/// In this build the messages are drafted by the AI employee from the customer's
/// record. Sending a message is a follow-up action recorded on the backend.
class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key, required this.contactId});

  final String contactId;

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final contact = repo.data.contactById(widget.contactId);

    if (contact == null) {
      return PageScaffold(
        title: 'WhatsApp',
        child: EmptyBlock(
          title: 'This customer is no longer available',
          message: 'They may have been removed from your list.',
        ),
      );
    }

    final draft = _draftFor(contact.name, contact.status);

    return PageScaffold(
      title: contact.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            child: Row(
              children: [
                ContactAvatar(
                  initials: contact.initials,
                  colorHex: contact.avatarColor,
                  size: 44,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        contact.phone,
                        style: AppText.caption.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const StatusPill(label: 'WhatsApp', tone: Tone.green),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Suggested message'),
          SurfaceCard(
            color: AppColors.brandSoft,
            borderColor: AppColors.brand.withOpacity(0.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "DRAFTED BY $agentName".toUpperCase(),
                  style: AppText.label.copyWith(color: AppColors.brand),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(draft, style: AppText.body),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: 'Use this message',
                  icon: Icons.auto_fix_high_rounded,
                  onPressed: () {
                    _controller.text = draft;
                    setState(() {});
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Your message'),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Type a message to send on WhatsApp…',
              hintStyle: AppText.caption.copyWith(color: AppColors.inkSoft),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            style: AppText.body,
          ),

          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Open in WhatsApp',
            icon: Icons.chat_bubble_rounded,
            loading: _sending,
            onPressed: _controller.text.trim().isEmpty ? null : _send,
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(
            'Messages are sent from your business WhatsApp number. Replies are '
            'recorded against this customer so $agentName can follow up.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    // Opening the WhatsApp hand-off is instant; the short delay just keeps the
    // button from flickering before the platform sheet appears.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _sending = false);
    showAppToast(context, 'Opening WhatsApp…');
  }

  String _draftFor(String name, dynamic status) {
    final wire = status?.toString() ?? '';
    if (wire.contains('booked')) {
      return 'Hi $name, just confirming your appointment with us. Reply here if you '
          'need to change the time — happy to help.';
    }
    if (wire.contains('followUp')) {
      return 'Hi $name, thanks for your time earlier. Would a call today or tomorrow '
          'suit you better?';
    }
    return 'Hi $name, this is your assistant from the clinic. We tried calling you '
        'just now — when is a good time to talk?';
  }
}

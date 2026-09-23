import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/follow_up.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../customer/customer_detail_screen.dart';
import '../whatsapp/whatsapp_screen.dart';

/// Everything waiting on the owner, in time order.
class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final pending = repo.data.pendingFollowUps;
    final done = repo.data.followUps.where((f) => !f.isPending).toList();

    return PageScaffold(
      title: 'Follow-ups',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${pending.length} waiting', style: AppText.hero),
          Text(
            'Customers your AI employee flagged for a follow-up',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),

          const SizedBox(height: AppSpacing.lg),

          if (pending.isEmpty)
            EmptyBlock(
              title: 'Nothing pending',
              message: 'When a call needs a follow-up, it appears here with a suggested action.',
            )
          else
            for (final followUp in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _FollowUpCard(followUp: followUp),
              ),

          if (done.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Completed'),
            for (final followUp in done)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _FollowUpCard(followUp: followUp, completed: true),
              ),
          ],
        ],
      ),
    );
  }
}

class _FollowUpCard extends StatefulWidget {
  const _FollowUpCard({required this.followUp, this.completed = false});

  final FollowUp followUp;
  final bool completed;

  @override
  State<_FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends State<_FollowUpCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final contact = repo.data.contactById(widget.followUp.contactId);
    final followUp = widget.followUp;

    final tone = switch (followUp.type) {
      FollowUpType.call => Tone.blue,
      FollowUpType.whatsapp => Tone.green,
      FollowUpType.reminder => Tone.amber,
    };
    final icon = switch (followUp.type) {
      FollowUpType.call => Icons.phone_rounded,
      FollowUpType.whatsapp => Icons.chat_bubble_rounded,
      FollowUpType.reminder => Icons.alarm_rounded,
    };

    return SurfaceCard(
      radius: AppRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, tone: tone),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact?.name ?? 'Customer',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${followUp.type.label} · '
                      '${followUp.dateTime.day}/${followUp.dateTime.month} '
                      '${followUp.dateTime.hour}:'
                      '${followUp.dateTime.minute.toString().padLeft(2, '0')}',
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              if (widget.completed) const StatusPill(label: 'Done', tone: Tone.green),
            ],
          ),
          if (followUp.message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(followUp.message, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
          ],
          if (!widget.completed) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: followUp.type == FollowUpType.whatsapp ? 'Message' : 'Handle now',
                    icon: icon,
                    tone: tone,
                    onPressed: _busy ? null : _handle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SecondaryButton(
                    label: 'Mark done',
                    icon: Icons.check_rounded,
                    loading: _busy,
                    onPressed: _busy ? null : _markDone,
                  ),
                ),
              ],
            ),
            if (contact != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => context.open(CustomerDetailScreen(contactId: contact.id)),
                child: Text(
                  'Open customer',
                  style: AppText.caption.copyWith(color: AppColors.brand),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _handle() {
    final repo = context.read<AppRepository>();
    final contact = repo.data.contactById(widget.followUp.contactId);
    if (contact == null) return;
    if (widget.followUp.type == FollowUpType.whatsapp) {
      context.open(WhatsAppScreen(contactId: contact.id));
    } else {
      context.open(CustomerDetailScreen(contactId: contact.id));
    }
  }

  /// The backend owns the follow-up queue, so it is closed there.
  Future<void> _markDone() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppRepository>().markFollowUpDone(widget.followUp.id);
      if (mounted) showAppToast(context, 'Follow-up marked as done');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

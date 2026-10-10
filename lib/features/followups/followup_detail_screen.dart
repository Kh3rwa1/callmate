import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import 'whatsapp_handoff.dart';
import 'followup_message_card.dart';

/// "Follow-up ready" – the signature screen.
class FollowUpDetailScreen extends ConsumerStatefulWidget {
  const FollowUpDetailScreen({super.key, required this.followUpId});
  final String followUpId;
  @override
  ConsumerState<FollowUpDetailScreen> createState() =>
      _FollowUpDetailScreenState();
}

class _FollowUpDetailScreenState extends ConsumerState<FollowUpDetailScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  bool _editing = false;
  bool _seeded = false;
  bool _awaitingReturn = false;
  bool _justOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// When the owner comes back from WhatsApp we show a sensible state –
  /// but we never claim the message was sent.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      if (mounted) setState(() => _justOpened = true);
    }
  }

  Future<void> _open(FollowUp fu) async {
    setState(() => _editing = false);
    final ok = await openWhatsAppHandoff(
      context,
      ref,
      phone: fu.leadPhone,
      message: _controller.text,
      followUp: fu,
    );
    if (ok && mounted) {
      setState(() {
        _awaitingReturn = true;
        _justOpened = true;
      });
    }
  }

  Future<void> _saveEdit(FollowUp fu) async {
    setState(() => _editing = false);
    if (_controller.text.trim() != fu.message.trim()) {
      await ref
          .read(followUpRepoProvider)
          .update(fu.copyWith(message: _controller.text.trim()));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message updated')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fuAsync = ref.watch(followUpProvider(widget.followUpId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          fuAsync.whenOrNull(
                data: (fu) => PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) async {
                    final wa = ref.read(whatsappServiceProvider);
                    if (v == 'copy') {
                      await wa.copyMessage(_controller.text);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message copied')),
                        );
                      }
                    } else if (v == 'share') {
                      await wa.shareMessage(_controller.text);
                    } else if (v == 'done') {
                      await ref
                          .read(followUpRepoProvider)
                          .update(fu.copyWith(status: FollowUpStatus.done));
                      if (context.mounted) context.pop();
                    } else if (v == 'dismiss') {
                      await ref
                          .read(followUpRepoProvider)
                          .update(
                            fu.copyWith(status: FollowUpStatus.dismissed),
                          );
                      if (context.mounted) context.pop();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy Message'),
                    ),
                    const PopupMenuItem(value: 'share', child: Text('Share…')),
                    if (!fu.isPending)
                      const PopupMenuItem(
                        value: 'done',
                        child: Text('I sent it'),
                      ),
                    const PopupMenuItem(
                      value: 'dismiss',
                      child: Text('Dismiss'),
                    ),
                  ],
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: AsyncView<FollowUp>(
        value: fuAsync,
        onRetry: () => ref.invalidate(followUpProvider(widget.followUpId)),
        data: (fu) {
          if (!_seeded) {
            _controller.text = fu.message;
            _seeded = true;
          }
          return _body(fu);
        },
      ),
    );
  }

  Widget _body(FollowUp fu) {
    final t = Theme.of(context).textTheme;
    final temp = LeadTemperature.fromScore(fu.scoreValue);
    final opened =
        _justOpened ||
        fu.status == FollowUpStatus.opened ||
        fu.status == FollowUpStatus.done;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              0,
              AppSpace.page,
              24,
            ),
            children: [
              const SizedBox(height: 4),
              Text(
                opened ? 'WhatsApp opened' : 'Follow-up ready',
                style: t.labelLarge?.copyWith(color: AppColors.inkFaint),
              ),
              const SizedBox(height: 6),
              Text(
                fu.leadName,
                style: t.headlineMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (fu.scoreValue != null) ...[
                    ScoreBadge(
                      score: LeadScore(
                        value: fu.scoreValue!,
                        temperature: temp,
                        intent: LeadIntent.unknown,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      PhoneUtils.display(fu.leadPhone),
                      style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (fu.callSummary != null) ...[
                const SizedBox(height: 20),
                AppCard(
                  key: const Key('followup-call-summary'),
                  shadow: false,
                  color: AppColors.surfaceMuted,
                  border: Border.all(color: Colors.transparent),
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  semanticLabel: 'Call summary',
                  onTap: fu.callId == null
                      ? null
                      : () => context.push('/calls/${fu.callId}/result'),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.call_outlined,
                        size: 18,
                        color: AppColors.inkSoft,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fu.callSummary!,
                          style: t.bodySmall?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (fu.callId != null)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.inkFaint,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FollowUpMessageCard(
                controller: _controller,
                editing: _editing,
                onTapToEdit: () => setState(() => _editing = true),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.inkFaint,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Nothing sends until you tap Send in WhatsApp',
                      style: t.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (opened) ...[
                const SizedBox(height: 20),
                AppCard(
                  color: AppColors.successSoft,
                  shadow: false,
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WhatsApp opened${fu.openedAt != null ? ' · ${Fmt.relative(fu.openedAt!)}' : ''}',
                              style: t.titleSmall,
                            ),
                            Text('Did you send it?', style: t.bodySmall),
                          ],
                        ),
                      ),
                      if (fu.status != FollowUpStatus.done)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.success,
                          ),
                          onPressed: () async {
                            await ref
                                .read(followUpRepoProvider)
                                .update(
                                  fu.copyWith(status: FollowUpStatus.done),
                                );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Marked as sent')),
                              );
                              context.pop();
                            }
                          },
                          child: const Text('I sent it'),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              12,
              AppSpace.page,
              12,
            ),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: _editing
                      ? () => _saveEdit(fu)
                      : () => setState(() => _editing = true),
                  icon: Icon(
                    _editing ? Icons.check_rounded : Icons.edit_outlined,
                    size: 19,
                  ),
                  label: Text(_editing ? 'Save' : 'Edit'),
                ),
                const SizedBox(width: 10),
                Expanded(child: WhatsAppButton(onPressed: () => _open(fu))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import 'whatsapp_handoff.dart';

/// "Follow-up ready 💬" – the signature screen.
class FollowUpDetailScreen extends ConsumerStatefulWidget {
  const FollowUpDetailScreen({super.key, required this.followUpId});
  final String followUpId;
  @override
  ConsumerState<FollowUpDetailScreen> createState() => _FollowUpDetailScreenState();
}

class _FollowUpDetailScreenState extends ConsumerState<FollowUpDetailScreen> with WidgetsBindingObserver {
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
    final ok = await openWhatsAppHandoff(context, ref, phone: fu.leadPhone, message: _controller.text, followUp: fu);
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
      await ref.read(followUpRepoProvider).update(fu.copyWith(message: _controller.text.trim()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message updated ✓')));
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
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
                    } else if (v == 'share') {
                      await wa.shareMessage(_controller.text);
                    } else if (v == 'done') {
                      await ref.read(followUpRepoProvider).update(fu.copyWith(status: FollowUpStatus.done));
                      if (context.mounted) context.pop();
                    } else if (v == 'dismiss') {
                      await ref.read(followUpRepoProvider).update(fu.copyWith(status: FollowUpStatus.dismissed));
                      if (context.mounted) context.pop();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('Copy Message')),
                    const PopupMenuItem(value: 'share', child: Text('Share…')),
                    if (!fu.isPending) const PopupMenuItem(value: 'done', child: Text('I sent it')),
                    const PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
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
    final opened = _justOpened || fu.status == FollowUpStatus.opened || fu.status == FollowUpStatus.done;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opened ? 'WhatsApp opened' : 'Follow-up ready\u00A0💬', style: t.headlineSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                fu.leadName,
                                style: t.titleLarge?.copyWith(color: AppColors.inkSoft),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (fu.scoreValue != null)
                              ScoreBadge(
                                score: LeadScore(value: fu.scoreValue!, temperature: temp, intent: LeadIntent.unknown),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(PhoneUtils.display(fu.leadPhone), style: t.bodySmall),
                      ],
                    ),
                  ),
                  Mascot(state: opened ? MascotState.success : MascotState.whatsapp, size: 96),
                ],
              ),
              if (fu.callSummary != null) ...[
                const SizedBox(height: 18),
                AppCard(
                  shadow: false,
                  color: AppColors.surfaceMuted,
                  padding: const EdgeInsets.all(14),
                  onTap: fu.callId == null ? null : () => context.push('/calls/${fu.callId}/result'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Emoji('📞', size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CALL SUMMARY', style: t.labelSmall),
                            const SizedBox(height: 4),
                            Text(
                              fu.callSummary!,
                              style: t.bodyMedium?.copyWith(color: AppColors.ink),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text('AI drafted this based on the call', style: t.titleSmall?.copyWith(color: AppColors.brand)),
                ],
              ),
              const SizedBox(height: 12),
              _MessageCard(controller: _controller, editing: _editing, onTapToEdit: () => setState(() => _editing = true)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.inkFaint),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Nothing is sent automatically. You tap Send in WhatsApp.', style: t.bodySmall)),
                ],
              ),
              if (opened) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: AppColors.successSoft,
                  shadow: false,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('WhatsApp opened${fu.openedAt != null ? ' · ${Fmt.relative(fu.openedAt!)}' : ''}', style: t.titleSmall),
                            Text('Did you send it? Mark it so ${ref.watch(employeeNameProvider)} knows.', style: t.bodySmall),
                          ],
                        ),
                      ),
                      if (fu.status != FollowUpStatus.done)
                        TextButton(
                          onPressed: () async {
                            await ref.read(followUpRepoProvider).update(fu.copyWith(status: FollowUpStatus.done));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as sent by you ✓')));
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
            padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 10),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _editing
                          ? SecondaryButton(label: 'Save', icon: Icons.check_rounded, onPressed: () => _saveEdit(fu))
                          : SecondaryButton(label: 'Edit Message', onPressed: () => setState(() => _editing = true)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: WhatsAppButton(onPressed: () => _open(fu))),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Opens WhatsApp with the message ready to send.', style: t.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// WhatsApp-style message bubble with gentle entrance animation.
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.controller, required this.editing, required this.onTapToEdit});
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
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
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
          border: Border.all(color: editing ? AppColors.whatsapp : const Color(0xFFCDEBC0), width: editing ? 2 : 1),
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
                        builder: (_, v, __) => Text(v.text, style: t.bodyLarge?.copyWith(height: 1.5)),
                      ),
                    ),
                  ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(editing ? 'Editing' : 'Draft', style: t.bodySmall?.copyWith(fontSize: 11.5)),
                const SizedBox(width: 4),
                const Icon(Icons.edit_note_rounded, size: 15, color: AppColors.inkFaint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

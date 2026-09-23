import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/call.dart';
import '../../models/contact.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../live_call/live_call_screen.dart';
import '../whatsapp/whatsapp_screen.dart';

/// One customer: their details, timeline and every call with them.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.contactId});

  final String contactId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _calling = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final contact = repo.data.contactById(widget.contactId);

    if (contact == null) {
      return PageScaffold(
        title: 'Customer',
        child: EmptyBlock(
          title: 'This customer is no longer available',
          message: 'They may have been removed from your list.',
        ),
      );
    }

    final calls = repo.data.calls.where((c) => c.contactId == contact.id).toList();

    return PageScaffold(
      title: 'Customer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                ContactAvatar(
                  initials: contact.initials,
                  colorHex: contact.avatarColor,
                  size: 72,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(contact.name, style: AppText.title, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  '${contact.service} · ${contact.phone}',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                StatusPill(label: contact.status.label, tone: Tone.green, large: true),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Call now',
                  icon: Icons.phone_rounded,
                  loading: _calling,
                  onPressed: _call,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_bubble_rounded,
                  onPressed: () =>
                      context.open(WhatsAppScreen(contactId: contact.id)),
                ),
              ),
            ],
          ),

          if (contact.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final tag in contact.tags) StatusPill(label: tag)],
            ),
          ],

          if (contact.recoveredAmount != null && contact.recoveredAmount! > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            SurfaceCard(
              color: AppColors.brandSoft,
              borderColor: AppColors.brand.withOpacity(0.2),
              child: Row(
                children: [
                  const IconTile(icon: Icons.savings_rounded, tone: Tone.green),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment recovered', style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                        Text(
                          '₹${contact.recoveredAmount!.toStringAsFixed(0)}',
                          style: AppText.title.copyWith(color: AppColors.brand),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (contact.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Notes'),
            SurfaceCard(
              child: Text(contact.notes, style: AppText.body),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Timeline'),
          if (contact.timeline.isEmpty)
            Text(
              'Nothing recorded yet.',
              style: AppText.caption.copyWith(color: AppColors.inkSoft),
            )
          else
            for (final entry in contact.timeline)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconTile(icon: Icons.circle, tone: Tone.neutral, size: 30),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (entry.detail != null && entry.detail!.isNotEmpty)
                            Text(
                              entry.detail!,
                              style: AppText.caption.copyWith(color: AppColors.inkSoft),
                            ),
                          Text(
                            '${entry.at.day}/${entry.at.month} · '
                            '${entry.at.hour}:${entry.at.minute.toString().padLeft(2, '0')}',
                            style: AppText.label.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Calls'),
          if (calls.isEmpty)
            Text(
              'No calls yet.',
              style: AppText.caption.copyWith(color: AppColors.inkSoft),
            )
          else
            for (final call in calls)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SurfaceCard(
                  radius: AppRadius.lg,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      IconTile(
                        icon: call.isLive ? Icons.phone_in_talk_rounded : Icons.call_rounded,
                        tone: call.isLive ? Tone.blue : Tone.neutral,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          call.summary.isEmpty ? call.status.label : call.summary,
                          style: AppText.caption.copyWith(color: AppColors.ink),
                        ),
                      ),
                      StatusPill(
                        label: call.outcome?.label ?? call.status.label,
                        tone: call.outcome == CallOutcome.booked ? Tone.green : Tone.neutral,
                      ),
                    ],
                  ),
                ),
              ),

          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: 'Edit details',
            icon: Icons.edit_rounded,
            onPressed: () => _edit(context, contact),
          ),
        ],
      ),
    );
  }

  Future<void> _call() async {
    if (_calling) return;
    setState(() => _calling = true);
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);
    try {
      final callId = await repo.startCall(contactId: widget.contactId);
      await repo.load();
      if (!mounted) return;
      navigator.push(MaterialPageRoute(builder: (_) => LiveCallScreen(callId: callId)));
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  Future<void> _edit(BuildContext context, Contact contact) async {
    final name = TextEditingController(text: contact.name);
    final phone = TextEditingController(text: contact.phone);
    final service = TextEditingController(text: contact.service);
    final notes = TextEditingController(text: contact.notes);
    final repo = context.read<AppRepository>();
    final hostContext = context;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? error;
        var saving = false;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> save() async {
              if (saving) return;
              setState(() {
                saving = true;
                error = null;
              });
              try {
                // Saved on the backend so the details the AI uses when calling
                // stay in sync with what the owner sees.
                await repo.updateContact(
                  contact.id,
                  name: name.text.trim(),
                  phone: phone.text.trim(),
                  service: service.text.trim(),
                  notes: notes.text,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                showAppToast(hostContext, '${name.text.trim()} updated');
              } on ApiException catch (e) {
                if (!dialogContext.mounted) return;
                setState(() {
                  saving = false;
                  error = e.message;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
              title: Text('Edit customer', style: AppText.title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(name, 'Name'),
                    const SizedBox(height: AppSpacing.md),
                    _field(phone, 'Phone', keyboard: TextInputType.phone),
                    const SizedBox(height: AppSpacing.md),
                    _field(service, 'Service'),
                    const SizedBox(height: AppSpacing.md),
                    _field(notes, 'Notes', lines: 3),
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(error!, style: AppText.caption.copyWith(
                          color: AppColors.coral,
                        )),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel', style: AppText.caption.copyWith(
                    color: AppColors.inkSoft,
                  )),
                ),
                PrimaryButton(label: 'Save changes', loading: saving, onPressed: save),
              ],
            );
          },
        );
      },
    );
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboard, int lines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.caption.copyWith(color: AppColors.inkSoft),
        filled: true,
        fillColor: AppColors.secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
      style: AppText.body,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/contact.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../customer/customer_detail_screen.dart';
import '../live_call/live_call_screen.dart';
import '../whatsapp/whatsapp_screen.dart';

/// The customer pipeline: pick a stage, see who is in it, act on a customer.
class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});

  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  ContactStatus _stage = ContactStatus.newLead;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final data = repo.data;
    final stages = ContactStatus.values;
    final inStage = data.contacts.where((c) => c.status == _stage).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pipeline', style: AppText.hero),
                      Text(
                        '${data.contacts.length} customers in total',
                        style: AppText.caption.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                SecondaryButton(
                  label: 'Add',
                  icon: Icons.person_add_alt_1_rounded,
                  expand: false,
                  tone: Tone.green,
                  onPressed: () => _showAddCustomer(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: stages.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final stage = stages[index];
                final count = data.contacts.where((c) => c.status == stage).length;
                return _StageChip(
                  label: '${stage.short} · $count',
                  selected: stage == _stage,
                  onTap: () => setState(() => _stage = stage),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Expanded(
            child: inStage.isEmpty
                ? Center(
                    child: EmptyBlock(
                      title: 'No customers here yet',
                      message: 'Customers move into this stage as your AI employee works through them.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, 32),
                    itemCount: inStage.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final contact = inStage[index];
                      return _CustomerCard(
                        contact: contact,
                        onTap: () => context.open(
                          CustomerDetailScreen(contactId: contact.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.brand : AppColors.border),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (contact.status) {
      ContactStatus.followUp => Tone.amber,
      ContactStatus.booked => Tone.green,
      ContactStatus.recovered => Tone.purple,
      ContactStatus.noResponse => Tone.coral,
      ContactStatus.calling => Tone.blue,
      _ => Tone.neutral,
    };

    return SurfaceCard(
      onTap: onTap,
      radius: AppRadius.xl,
      child: Column(
        children: [
          Row(
            children: [
              ContactAvatar(initials: contact.initials, colorHex: contact.avatarColor, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      contact.service,
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              StatusPill(label: contact.status.label, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                contact.lastCallOutcome ?? 'Not called yet',
                style: AppText.caption.copyWith(color: AppColors.inkSoft),
              ),
              const Spacer(),
              _MiniAction(
                label: 'Call',
                icon: Icons.phone_rounded,
                onTap: () => _startCall(context, contact),
              ),
              const SizedBox(width: AppSpacing.sm),
              _MiniAction(
                label: 'WhatsApp',
                icon: Icons.chat_bubble_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WhatsAppScreen(contactId: contact.id),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(BuildContext context, Contact contact) async {
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);
    try {
      final callId = await repo.startCall(contactId: contact.id);
      await repo.load();
      if (!context.mounted) return;
      navigator.push(MaterialPageRoute(builder: (_) => LiveCallScreen(callId: callId)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, e.message);
    }
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: AppColors.ink),
              const SizedBox(width: 5),
              Text(label, style: AppText.label.copyWith(color: AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds a customer, stored on the backend so the calling round can use them.
Future<void> _showAddCustomer(BuildContext context) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final service = TextEditingController();
  final repo = context.read<AppRepository>();
  final messengerContext = context;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      String? error;
      var saving = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> save() async {
            if (saving) return;
            if (name.text.trim().isEmpty) {
              setState(() => error = 'Please enter the customer name');
              return;
            }
            if (phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
              setState(() => error = 'Please enter a valid phone number');
              return;
            }
            setState(() {
              saving = true;
              error = null;
            });
            try {
              await repo.createContact(
                name: name.text.trim(),
                phone: phone.text.trim(),
                service: service.text.trim().isEmpty ? 'Enquiry' : service.text.trim(),
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              showAppToast(messengerContext, '${name.text.trim()} added to the pipeline');
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
            title: Text('Add a customer', style: AppText.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(controller: name, label: 'Name'),
                const SizedBox(height: AppSpacing.md),
                _DialogField(controller: phone, label: 'Phone', keyboard: TextInputType.phone),
                const SizedBox(height: AppSpacing.md),
                _DialogField(controller: service, label: 'Service (optional)'),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: AppText.caption.copyWith(color: AppColors.coral),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel', style: AppText.caption.copyWith(color: AppColors.inkSoft)),
              ),
              PrimaryButton(
                label: 'Add customer',
                loading: saving,
                onPressed: save,
              ),
            ],
          );
        },
      );
    },
  );
}

class _DialogField extends StatelessWidget {
  const _DialogField({required this.controller, required this.label, this.keyboard});

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
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

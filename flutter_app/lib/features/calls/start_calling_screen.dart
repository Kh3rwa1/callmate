import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/campaign.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import 'campaign_screen.dart';

/// Chooses who to call, why, and when — then asks the backend to start the round.
class StartCallingScreen extends StatefulWidget {
  const StartCallingScreen({super.key});

  @override
  State<StartCallingScreen> createState() => _StartCallingScreenState();
}

class _StartCallingScreenState extends State<StartCallingScreen> {
  final Set<String> _selected = {};
  String _purpose = 'appointment';
  DateTime? _scheduledFor;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to everyone who still needs a call.
    final data = context.read<AppRepository>().data;
    for (final contact in data.contacts) {
      if (contact.status == ContactStatus.newLead) _selected.add(contact.id);
    }
    if (_selected.isEmpty) {
      for (final contact in data.contacts) {
        _selected.add(contact.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppRepository>().data;

    return PageScaffold(
      title: 'Start calling',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(label: 'READY TO CALL', tone: Tone.green, large: true),
          const SizedBox(height: AppSpacing.md),
          Text('${data.contacts.length} customers in your list', style: AppText.hero),

          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'What is this round for?'),
          for (final purpose in kCampaignPurposes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SecondaryButton(
                label: '${kCampaignPurposeLabels[purpose]} — ${kCampaignPurposeHints[purpose]}',
                selected: _purpose == purpose,
                tone: Tone.green,
                onPressed: () => setState(() => _purpose = purpose),
              ),
            ),

          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'When should $agentName call?'),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Now',
                  selected: _scheduledFor == null,
                  tone: Tone.green,
                  onPressed: () => setState(() => _scheduledFor = null),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: _scheduledFor == null
                      ? 'Schedule'
                      : '${_scheduledFor!.day}/${_scheduledFor!.month} '
                          '${_scheduledFor!.hour}:${_scheduledFor!.minute.toString().padLeft(2, '0')}',
                  selected: _scheduledFor != null,
                  tone: Tone.green,
                  onPressed: _pickSchedule,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: 'Who to call',
            action: TextButton(
              onPressed: () => setState(() {
                if (_selected.length == data.contacts.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(data.contacts.map((c) => c.id));
                }
              }),
              child: Text(
                _selected.length == data.contacts.length ? 'Clear' : 'Select all',
                style: AppText.caption.copyWith(color: AppColors.brand),
              ),
            ),
          ),
          for (final contact in data.contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SurfaceCard(
                radius: AppRadius.lg,
                padding: const EdgeInsets.all(AppSpacing.md),
                borderColor: _selected.contains(contact.id)
                    ? AppColors.brand
                    : AppColors.border,
                onTap: () => setState(() {
                  if (!_selected.remove(contact.id)) _selected.add(contact.id);
                }),
                child: Row(
                  children: [
                    Icon(
                      _selected.contains(contact.id)
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: _selected.contains(contact.id)
                          ? AppColors.brand
                          : AppColors.inkSoft,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    ContactAvatar(
                      initials: contact.initials,
                      colorHex: contact.avatarColor,
                      size: 36,
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
                            contact.service,
                            style: AppText.caption.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(label: contact.status.label, tone: Tone.neutral),
                  ],
                ),
              ),
            ),

          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: AppText.caption.copyWith(color: AppColors.coral)),
          ],

          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: _scheduledFor == null ? 'Start calling' : 'Schedule round',
            icon: Icons.phone_forwarded_rounded,
            loading: _busy,
            onPressed: _selected.isEmpty ? null : _start,
          ),
        ],
      ),
    );
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);

    try {
      // The backend creates the round and, when live, starts the provider
      // campaign that actually places the calls.
      final campaignId = await repo.startCampaign(
        CampaignDraft(
          purpose: _purpose,
          contactIds: _selected.toList(),
          scheduledFor: _scheduledFor,
        ),
      );
      await repo.load();
      if (!mounted) return;

      if (_scheduledFor != null) {
        showAppToast(context, 'Round scheduled. $agentName will start on time.');
        navigator.pop();
        return;
      }

      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => CampaignScreen(campaignId: campaignId)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/call.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../call_result/call_result_screen.dart';

/// The live call screen.
///
/// The call itself is placed by the backend, which talks to the voice provider,
/// and the outcome is recorded by the backend too. This screen shows the call in
/// progress and lets the user record what happened — it never invents a business
/// result locally, so the pipeline always matches the call record.
///
/// The full transcript is deliberately NOT shown here; it is loaded on demand
/// from the call result screen.
class LiveCallScreen extends StatefulWidget {
  const LiveCallScreen({super.key, required this.callId});

  final String callId;

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen> {
  Timer? _timer;
  int _elapsed = 0;
  bool _muted = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    final call = context.read<AppRepository>().data.callById(widget.callId);
    if (call != null) {
      _elapsed = DateTime.now().difference(call.startedAt).inSeconds.clamp(0, 86400);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final call = repo.data.callById(widget.callId);
    final contact = call == null ? null : repo.data.contactById(call.contactId);

    if (call == null) {
      return PageScaffold(
        title: 'Call',
        child: EmptyBlock(
          title: 'This call has ended',
          message: 'You can find its result in your call history.',
          actionLabel: 'Back to calls',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final connected = _elapsed > 4;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              StatusPill(
                label: connected ? 'Connected' : 'Connecting',
                tone: connected ? Tone.green : Tone.blue,
                large: true,
              ),
              const Spacer(),
              Mascot(
                mood: connected ? MascotMood.happy : MascotMood.calling,
                size: 108,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                connected
                    ? 'Talking to ${contact?.name ?? 'customer'}…'
                    : 'Calling ${contact?.name ?? 'customer'}…',
                textAlign: TextAlign.center,
                style: AppText.hero,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                formatDuration(_elapsed),
                style: AppText.display.copyWith(fontSize: 40),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                contact?.service ?? 'Outbound call',
                style: AppText.caption.copyWith(color: AppColors.inkSoft),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.purpleSoft,
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  border: Border.all(color: AppColors.purple.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: AppColors.purple),
                        const SizedBox(width: 6),
                        Text(
                          "$agentName'S INSIGHT",
                          style: AppText.label.copyWith(color: AppColors.purple),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(insightFor(contact?.status), style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'How did this call go?',
                style: AppText.caption.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final outcome in CallOutcome.values)
                    SecondaryButton(
                      label: outcome.label,
                      expand: false,
                      tone: switch (outcome) {
                        CallOutcome.booked || CallOutcome.recovered => Tone.green,
                        CallOutcome.interested => Tone.purple,
                        CallOutcome.followUp => Tone.amber,
                        CallOutcome.noResponse => Tone.coral,
                        _ => Tone.neutral,
                      },
                      onPressed: _finishing ? null : () => _finish(outcome),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleIconButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: 'Mute',
                    tone: _muted ? Tone.coral : Tone.neutral,
                    onPressed: () => setState(() => _muted = !_muted),
                  ),
                  const SizedBox(width: AppSpacing.xxl),
                  CircleIconButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    tone: Tone.coral,
                    size: 66,
                    onPressed: _finishing ? null : () => _finish(CallOutcome.followUp),
                  ),
                  const SizedBox(width: AppSpacing.xxl),
                  CircleIconButton(
                    icon: Icons.info_outline_rounded,
                    label: 'Details',
                    onPressed: () => _showDetails(context, contact),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish(CallOutcome outcome) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);

    try {
      // The backend records the outcome, moves the customer and opens any
      // follow-up; we then show its result screen.
      await repo.completeCall(callId: widget.callId, outcome: outcome);
      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => CallResultScreen(callId: widget.callId)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showAppToast(context, e.message);
    }
  }

  void _showDetails(BuildContext context, dynamic contact) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Call details', style: AppText.title),
            const SizedBox(height: AppSpacing.lg),
            _DetailRow(label: 'Customer', value: contact?.name ?? 'Unknown'),
            _DetailRow(label: 'Phone', value: contact?.phone ?? '—'),
            _DetailRow(label: 'Service', value: contact?.service ?? '—'),
            _DetailRow(label: 'Duration', value: formatDuration(_elapsed)),
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Text(label, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.caption.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The note our employee keeps about a customer, shown during a call.
String insightFor(dynamic status) {
  final wire = status?.toString() ?? '';
  if (wire.contains('followUp')) return 'Warm lead. Ask which time works best.';
  if (wire.contains('booked')) return 'Already booked. Confirm the appointment details.';
  if (wire.contains('recovered')) return 'Payment collected. Thank the customer.';
  if (wire.contains('noResponse')) return 'Has not picked up before. Keep it brief.';
  if (wire.contains('notInterested')) return 'Was not interested earlier.';
  return 'A brand new enquiry — the first conversation matters most.';
}

/// Formats seconds as `m:ss`.
String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

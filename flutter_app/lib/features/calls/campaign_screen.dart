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
import '../call_result/call_result_screen.dart';
import 'calls_screen.dart';
import 'start_calling_screen.dart';

/// How often we ask the backend to advance the round and report progress.
const _tickInterval = Duration(milliseconds: 2600);

/// A running calling round.
///
/// Each tick asks the backend to advance one call. The backend decides what
/// happened — in mock mode it simulates, in live mode the real provider makes the
/// call and its webhook reports back — and we simply re-read the result.
class CampaignScreen extends StatefulWidget {
  const CampaignScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen> {
  Timer? _timer;
  bool _advancing = false;
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tickInterval, (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _advance() async {
    final repo = context.read<AppRepository>();
    final campaign = repo.data.campaignById(widget.campaignId);
    if (campaign == null || campaign.status != CampaignStatus.running) return;
    if (_advancing) return;

    _advancing = true;
    try {
      await repo.advanceCampaign(widget.campaignId);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } finally {
      _advancing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final campaign = repo.data.campaignById(widget.campaignId);

    if (campaign == null) {
      return PageScaffold(
        title: 'Calling round',
        child: EmptyBlock(
          title: 'This round has finished',
          message: 'Start a new calling round and $agentName will get to work.',
          actionLabel: 'Start calling',
          onAction: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const StartCallingScreen()),
          ),
        ),
      );
    }

    if (campaign.status == CampaignStatus.completed && !_announced) {
      _announced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAppToast(context, 'Calling round finished · ${campaign.booked} booked');
        }
      });
    }

    final running = campaign.status == CampaignStatus.running;
    final campaignCalls = repo.data.callsForCampaign(campaign.id).take(4).toList();
    final nextContact = campaign.completed < campaign.contactIds.length
        ? repo.data.contactById(campaign.contactIds[campaign.completed])
        : null;

    return PageScaffold(
      title: 'Calling round',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(
            label: campaign.status.label,
            tone: running ? Tone.blue : Tone.green,
            large: true,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? '$agentName is calling' : 'Calling round',
                      style: AppText.hero,
                    ),
                    Text(
                      '${campaign.total} customers · ${campaign.purposeLabel}',
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Mascot(
                mood: running ? MascotMood.calling : MascotMood.celebrating,
                size: 72,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${campaign.completed}', style: AppText.display),
                    Text(
                      ' / ${campaign.total}',
                      style: AppText.title.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: campaign.total == 0 ? 0 : campaign.completed / campaign.total,
                    minHeight: 8,
                    backgroundColor: AppColors.secondary,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'calls done',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          if (running && nextContact != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                border: Border.all(color: AppColors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  ContactAvatar(
                    initials: nextContact.initials,
                    colorHex: nextContact.avatarColor,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CALLING NOW',
                          style: AppText.label.copyWith(color: AppColors.blue),
                        ),
                        Text(
                          nextContact.name,
                          style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const StatusPill(label: 'Live', tone: Tone.blue),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _Stat(label: 'Booked', value: campaign.booked, tone: Tone.green),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(label: 'Interested', value: campaign.interested, tone: Tone.purple),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(label: 'Follow-ups', value: campaign.followUps, tone: Tone.amber),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(label: 'No answer', value: campaign.noAnswer, tone: Tone.coral),
              ),
            ],
          ),
          if (campaignCalls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Latest results'),
            for (final call in campaignCalls)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: CallRow(
                  call: call,
                  contactName: repo.data.contactById(call.contactId)?.name ?? 'Customer',
                  initials: repo.data.contactById(call.contactId)?.initials ?? '?',
                  colorHex:
                      repo.data.contactById(call.contactId)?.avatarColor ?? '#18C97A',
                  onTap: () => context.open(CallResultScreen(callId: call.id)),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'View calls',
            dark: true,
            icon: Icons.list_alt_rounded,
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const _CallsTabHost()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (running)
            SecondaryButton(
              label: 'Stop calling',
              icon: Icons.phone_disabled_rounded,
              tone: Tone.coral,
              onPressed: _stop,
            )
          else
            SecondaryButton(
              label: 'Start a new round',
              icon: Icons.refresh_rounded,
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const StartCallingScreen()),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '$agentName reports each result as the call finishes and updates your '
            'pipeline straight away.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _stop() async {
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);
    try {
      await repo.stopCampaign(widget.campaignId);
      if (!mounted) return;
      showAppToast(context, 'Calling round stopped');
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const _CallsTabHost()),
      );
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    }
  }
}

/// Returns to the shell with the Calls tab showing.
class _CallsTabHost extends StatelessWidget {
  const _CallsTabHost();

  @override
  Widget build(BuildContext context) => const Scaffold(body: CallsScreen());
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text('$value', style: AppText.title.copyWith(color: tone.foreground)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: tone.foreground),
          ),
        ],
      ),
    );
  }
}

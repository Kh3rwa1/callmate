import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import 'campaign_setup_widgets.dart';

// =============================================================== Setup
class CampaignSetupScreen extends ConsumerStatefulWidget {
  const CampaignSetupScreen({super.key});
  @override
  ConsumerState<CampaignSetupScreen> createState() =>
      _CampaignSetupScreenState();
}

class _CampaignSetupScreenState extends ConsumerState<CampaignSetupScreen> {
  var _opts = const CampaignOptions();
  bool _starting = false;
  RangeValues? _hours;

  Future<void> _start(List<Lead> leads, Agent agent) async {
    final repo = ref.read(campaignRepoProvider);
    // The backend never calls DNC / opted-out leads, and skips leads with
    // unknown consent unless the owner attests to it.
    final blocked = leads
        .where((l) => l.doNotCall || l.consent == 'opt_out')
        .length;
    final skippedNoConsent = leads
        .where((l) => !l.doNotCall && l.consent == 'unknown')
        .length;
    var consentAttestation = false;
    int callable() =>
        leads.length - blocked - (consentAttestation ? 0 : skippedNoConsent);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  0,
                  AppSpace.page,
                  16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Mascot(state: MascotState.calling, size: 88),
                    const SizedBox(height: 8),
                    Text(
                      callable() == 0
                          ? 'No leads to call yet'
                          : 'Start calling ${callable()} leads?',
                      style: t.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${Fmt.hour(_hours!.start.round())} – ${Fmt.hour(_hours!.end.round())} · ${agent.name} says she is an AI assistant',
                      style: t.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (skippedNoConsent > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              consentAttestation
                                  ? '$skippedNoConsent leads have no consent recorded'
                                  : '$skippedNoConsent leads will be skipped (no consent recorded)',
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Checkbox(
                                  value: consentAttestation,
                                  onChanged: (v) {
                                    setModalState(() {
                                      consentAttestation = v ?? false;
                                    });
                                  },
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() {
                                        consentAttestation =
                                            !consentAttestation;
                                      });
                                    },
                                    child: Text(
                                      'I confirm these contacts asked to be contacted',
                                      style: t.bodySmall,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Estimated usage', style: t.bodyMedium),
                        const Spacer(),
                        Text(
                          '≈ ${Fmt.inr(repo.estimateCostInr(callable()))}',
                          style: t.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Yes, start calling',
                      icon: Icons.phone_forwarded_rounded,
                      onPressed: callable() == 0
                          ? null
                          : () => Navigator.pop(ctx, true),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    setState(() => _starting = true);
    try {
      final draft = CampaignDraft(
        leadIds: leads.map((e) => e.id).toList(),
        purpose: ref.read(businessTemplateProvider).agent.callPurpose,
        callingHoursStart: _hours!.start.round(),
        callingHoursEnd: _hours!.end.round(),
        options: _opts,
      );
      final c = await repo.create(draft);
      final started = await repo.start(
        c.id,
        consentAttestation: consentAttestation,
      );
      ref.read(activeCampaignProvider.notifier).set(started);
      ref.read(analyticsProvider).track('campaign_started', {
        'leads': leads.length,
      });
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${agent.name} is on it')));
      context.pushReplacement('/campaigns/${c.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final leadsAsync = ref.watch(newLeadsProvider);
    final agent = ref.watch(agentProvider).value;
    _hours ??= RangeValues(
      (agent?.callingHoursStart ?? 10).toDouble(),
      (agent?.callingHoursEnd ?? 19).toDouble(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Call New Leads')),
      body: AsyncView<List<Lead>>(
        value: leadsAsync,
        onRetry: () => ref.invalidate(newLeadsProvider),
        data: (leads) {
          if (leads.isEmpty) {
            return EmptyState(
              title: 'No new leads to call',
              message: 'Add leads to start calling.',
              actionLabel: 'Add leads',
              onAction: () => context.pushReplacement('/leads/import'),
            );
          }
          final cost = ref
              .read(campaignRepoProvider)
              .estimateCostInr(leads.length);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    4,
                    AppSpace.page,
                    24,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${leads.length}',
                                  style: t.displayMedium?.copyWith(
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'leads ready',
                                  style: t.titleMedium?.copyWith(
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Mascot(state: MascotState.calling, size: 76),
                        ],
                      ),
                    ),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: Column(
                        children: [
                          CampaignSummaryRow(
                            label: 'Caller',
                            value: agent?.name ?? '—',
                            leading: const MascotAvatar(size: 26),
                          ),
                          const Divider(height: 1),
                          CampaignSummaryRow(
                            label: 'Purpose',
                            value: ref
                                .watch(businessTemplateProvider)
                                .agent
                                .callPurpose,
                          ),
                          const Divider(height: 1),
                          const CampaignSummaryRow(
                            label: 'Language',
                            value: 'Auto detect',
                          ),
                          const Divider(height: 1),
                          CampaignSummaryRow(
                            label: 'Calling hours',
                            value:
                                '${Fmt.hour(_hours!.start.round())} – ${Fmt.hour(_hours!.end.round())}',
                          ),
                          RangeSlider(
                            values: _hours!,
                            min: 8,
                            max: 21,
                            divisions: 13,
                            labels: RangeLabels(
                              Fmt.hour(_hours!.start.round()),
                              Fmt.hour(_hours!.end.round()),
                            ),
                            onChanged: (v) {
                              if (v.end - v.start >= 2) {
                                setState(() => _hours = v);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SectionLabel('After each call'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          CampaignChecklistItem(
                            'Score lead',
                            _opts.scoreLead,
                            (v) => setState(
                              () => _opts = _opts.copyWith(scoreLead: v),
                            ),
                          ),
                          CampaignChecklistItem(
                            'Generate WhatsApp follow-up',
                            _opts.generateWhatsapp,
                            (v) => setState(
                              () => _opts = _opts.copyWith(generateWhatsapp: v),
                            ),
                          ),
                          CampaignChecklistItem(
                            'Recommend callback',
                            _opts.recommendCallback,
                            (v) => setState(
                              () =>
                                  _opts = _opts.copyWith(recommendCallback: v),
                            ),
                          ),
                          CampaignChecklistItem(
                            'Notify me for hot leads',
                            _opts.notifyHot,
                            (v) => setState(
                              () => _opts = _opts.copyWith(notifyHot: v),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 20, 2, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Estimated usage', style: t.titleSmall),
                                Text(
                                  'Connected minutes only',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text('≈ ${Fmt.inr(cost)}', style: t.titleMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    8,
                    AppSpace.page,
                    12,
                  ),
                  child: PrimaryButton(
                    label: 'Start Campaign',
                    icon: Icons.phone_forwarded_rounded,
                    loading: _starting,
                    onPressed: agent == null
                        ? null
                        : () => _start(leads, agent),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

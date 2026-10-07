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
    final cost = repo.estimateCostInr(leads.length);
    final skippedNoConsent = leads.where((l) => !l.hasConsent).length;
    var consentAttestation = false;

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
                    const Mascot(state: MascotState.calling, size: 120),
                    const SizedBox(height: 12),
                    Text(
                      'Start calling ${leads.length} leads?',
                      style: t.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${agent.name} will call between ${Fmt.hour(_hours!.start.round())} and ${Fmt.hour(_hours!.end.round())}, '
                      'introduce herself as an AI assistant, and notify you about hot leads.',
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
                              '$skippedNoConsent leads skipped (no consent recorded)',
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
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Text('Estimated usage', style: t.bodyMedium),
                          const Spacer(),
                          Text('≈ ${Fmt.inr(cost)}', style: t.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: '🚀  Yes, start calling',
                      color: AppColors.brand,
                      onPressed: () => Navigator.pop(ctx, true),
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
      ).showSnackBar(SnackBar(content: Text('${agent.name} is on it 🚀')));
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
              message:
                  'Your AI employee is ready. Add your first leads to start calling.',
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
                    AppCard(
                      child: Row(
                        children: [
                          const Mascot(state: MascotState.calling, size: 96),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${leads.length}',
                                  style: t.displaySmall?.copyWith(
                                    color: AppColors.brand,
                                  ),
                                ),
                                Text('leads ready', style: t.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  '${agent?.name ?? 'Your AI employee'} will call each one and report back.',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          CampaignSummaryRow(
                            label: 'AI Employee',
                            value: agent == null
                                ? '—'
                                : '${agent.name} · ${agent.role}',
                            leading: const MascotAvatar(size: 30),
                          ),
                          const Divider(),
                          CampaignSummaryRow(
                            label: 'Purpose',
                            value: ref
                                .watch(businessTemplateProvider)
                                .agent
                                .callPurpose,
                          ),
                          const Divider(),
                          const CampaignSummaryRow(
                            label: 'Languages',
                            value: 'Auto detect',
                          ),
                          const Divider(),
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
                    const SizedBox(height: 14),
                    AppCard(
                      color: AppColors.surfaceMuted,
                      shadow: false,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Emoji('💳', size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Estimated usage', style: t.bodyMedium),
                          ),
                          Text('≈ ${Fmt.inr(cost)}', style: t.titleMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Only connected minutes are counted. Deducted from your plan minutes first.',
                        style: t.bodySmall,
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
                    label: '🚀  Start Campaign',
                    loading: _starting,
                    color: AppColors.brand,
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

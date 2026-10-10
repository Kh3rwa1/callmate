import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
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

  String _hoursLabel() =>
      '${Fmt.hour(_hours!.start.round())} – ${Fmt.hour(_hours!.end.round())}';

  Future<void> _start(List<Lead> leads, Agent agent) async {
    final s = context.s;
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
            final n = callable();
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
                    SwapFade(
                      child: Text(
                        n == 0 ? s.noLeadsToCallYet : s.startCallingN(n),
                        key: ValueKey(n),
                        style: t.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.campaignDisclosure(_hoursLabel(), agent.name),
                      style: t.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (skippedNoConsent > 0) ...[
                      const SizedBox(height: 12),
                      AnimatedContainer(
                        duration: AppMotion.of(ctx, AppMotion.base),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: consentAttestation
                              ? AppColors.successSoft
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: consentAttestation
                                ? AppColors.success
                                : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              consentAttestation
                                  ? s.noConsentWarn(skippedNoConsent)
                                  : s.noConsentSkipped(skippedNoConsent),
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.inkSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Haptics.tap();
                                setModalState(
                                  () =>
                                      consentAttestation = !consentAttestation,
                                );
                              },
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: consentAttestation,
                                    onChanged: (v) => setModalState(
                                      () => consentAttestation = v ?? false,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      s.consentAttest,
                                      style: t.bodySmall?.copyWith(
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(s.estimatedUsage, style: t.bodyMedium),
                        const Spacer(),
                        AnimatedCount(
                          value: repo.estimateCostInr(n),
                          format: (v) => '≈ ${Fmt.inr(v)}',
                          duration: const Duration(milliseconds: 400),
                          style: t.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: s.yesStartCalling,
                      icon: Icons.phone_forwarded_rounded,
                      onPressed: n == 0 ? null : () => Navigator.pop(ctx, true),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(s.notNow),
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
      Haptics.warn();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.isOnIt(agent.name))));
      context.pushReplacement('/campaigns/${c.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final leadsAsync = ref.watch(newLeadsProvider);
    final agent = ref.watch(agentProvider).value;
    _hours ??= RangeValues(
      (agent?.callingHoursStart ?? 10).toDouble(),
      (agent?.callingHoursEnd ?? 19).toDouble(),
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.campaignSetupTitle)),
      body: AsyncView<List<Lead>>(
        value: leadsAsync,
        onRetry: () => ref.invalidate(newLeadsProvider),
        data: (leads) {
          if (leads.isEmpty) {
            return EmptyState(
              title: s.noNewLeadsToCall,
              message: s.addLeadsToStart,
              actionLabel: s.addLeads,
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
                    Reveal(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedCount(
                                    value: leads.length,
                                    countUp: true,
                                    duration: const Duration(milliseconds: 700),
                                    style: t.displayMedium?.copyWith(
                                      height: 1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    s.leadsReady,
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
                    ),
                    Reveal(
                      index: 1,
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Column(
                          children: [
                            CampaignSummaryRow(
                              label: s.campaignCaller,
                              value: agent?.name ?? '—',
                              leading: const MascotAvatar(size: 26),
                            ),
                            const Divider(height: 1),
                            CampaignSummaryRow(
                              label: s.campaignPurpose,
                              value: s.data(
                                ref
                                    .watch(businessTemplateProvider)
                                    .agent
                                    .callPurpose,
                              ),
                            ),
                            const Divider(height: 1),
                            CampaignSummaryRow(
                              label: s.campaignLanguage,
                              value: s.autoDetect,
                            ),
                            const Divider(height: 1),
                            CampaignSummaryRow(
                              label: s.callingHours,
                              value: _hoursLabel(),
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
                                  if (v != _hours) Haptics.tap();
                                  setState(() => _hours = v);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Reveal(index: 2, child: SectionLabel(s.afterEachCall)),
                    Reveal(
                      index: 3,
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            CampaignChecklistItem(
                              s.optScoreLead,
                              _opts.scoreLead,
                              (v) => setState(
                                () => _opts = _opts.copyWith(scoreLead: v),
                              ),
                            ),
                            CampaignChecklistItem(
                              s.optWhatsapp,
                              _opts.generateWhatsapp,
                              (v) => setState(
                                () =>
                                    _opts = _opts.copyWith(generateWhatsapp: v),
                              ),
                            ),
                            CampaignChecklistItem(
                              s.optCallback,
                              _opts.recommendCallback,
                              (v) => setState(
                                () => _opts = _opts.copyWith(
                                  recommendCallback: v,
                                ),
                              ),
                            ),
                            CampaignChecklistItem(
                              s.optNotifyHot,
                              _opts.notifyHot,
                              (v) => setState(
                                () => _opts = _opts.copyWith(notifyHot: v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Reveal(
                      index: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 20, 2, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.estimatedUsage, style: t.titleSmall),
                                  Text(
                                    s.connectedMinutesOnly,
                                    style: t.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text('≈ ${Fmt.inr(cost)}', style: t.titleMedium),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    10,
                    AppSpace.page,
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border(top: BorderSide(color: AppColors.hairline)),
                  ),
                  child: PrimaryButton(
                    label: s.startCampaign,
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

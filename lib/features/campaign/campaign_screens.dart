import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

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
                          _Row(
                            label: 'AI Employee',
                            value: agent == null
                                ? '—'
                                : '${agent.name} · ${agent.role}',
                            leading: const MascotAvatar(size: 30),
                          ),
                          const Divider(),
                          _Row(
                            label: 'Purpose',
                            value: ref
                                .watch(businessTemplateProvider)
                                .agent
                                .callPurpose,
                          ),
                          const Divider(),
                          const _Row(label: 'Languages', value: 'Auto detect'),
                          const Divider(),
                          _Row(
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
                          _Check(
                            'Score lead',
                            _opts.scoreLead,
                            (v) => setState(
                              () => _opts = _opts.copyWith(scoreLead: v),
                            ),
                          ),
                          _Check(
                            'Generate WhatsApp follow-up',
                            _opts.generateWhatsapp,
                            (v) => setState(
                              () => _opts = _opts.copyWith(generateWhatsapp: v),
                            ),
                          ),
                          _Check(
                            'Recommend callback',
                            _opts.recommendCallback,
                            (v) => setState(
                              () =>
                                  _opts = _opts.copyWith(recommendCallback: v),
                            ),
                          ),
                          _Check(
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.leading});
  final String label;
  final String value;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(label, style: t.bodyMedium),
          const Spacer(),
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(value, style: t.titleSmall, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    onChanged: (v) {
      HapticFeedback.selectionClick();
      onChanged(v ?? false);
    },
    title: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
  );
}

// ============================================================ Progress
class CampaignProgressScreen extends ConsumerWidget {
  const CampaignProgressScreen({super.key, required this.campaignId});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(activeCampaignProvider);
    final c = live?.id == campaignId ? live : null;
    final t = Theme.of(context).textTheme;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: FutureBuilder<Campaign>(
          future: ref.read(campaignRepoProvider).get(campaignId),
          builder: (context, snap) {
            if (snap.hasData) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) =>
                    ref.read(activeCampaignProvider.notifier).set(snap.data!),
              );
            }
            if (snap.hasError) {
              return ErrorState(
                message: friendlyError(snap.error!),
                onRetry: () => context.pop(),
              );
            }
            return const SkeletonList(count: 3);
          },
        ),
      );
    }
    final s = c.stats;
    final running = c.isActive;
    final done = c.status == CampaignStatus.completed;
    final agentName = ref.watch(employeeNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign'),
        actions: [
          if (running)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Pause calling?'),
                    content: Text(
                      '$agentName will stop after the current call. Remaining leads stay in your list.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep going'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Stop',
                          style: TextStyle(color: AppColors.hot),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final stopped = await ref
                      .read(campaignRepoProvider)
                      .stop(c.id);
                  ref.read(activeCampaignProvider.notifier).set(stopped);
                }
              },
              child: const Text('Stop', style: TextStyle(color: AppColors.hot)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 32),
        children: [
          AppCard(
            child: Column(
              children: [
                Mascot(
                  state: done
                      ? MascotState.success
                      : (running ? MascotState.calling : MascotState.welcome),
                  size: 150,
                ),
                const SizedBox(height: 10),
                Text(
                  done
                      ? '$agentName finished calling ✓'
                      : (running
                            ? '$agentName is doing the work for you'
                            : 'Campaign stopped'),
                  style: t.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  running
                      ? 'You\'ll get a notification for every hot lead.'
                      : '${s.completed} of ${s.total} leads called',
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: s.progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Column(
                    children: [
                      LinearProgressIndicator(
                        value: v,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(9),
                        backgroundColor: AppColors.brandSoft,
                        color: done ? AppColors.success : AppColors.brand,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('${(v * 100).round()}%', style: t.titleSmall),
                          const Spacer(),
                          Text('${s.remaining} remaining', style: t.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Status'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              _Stat('Queued', s.queued, AppColors.inkSoft),
              _Stat('Completed', s.completed, AppColors.ink),
              _Stat('Connected', s.connected, AppColors.success),
              _Stat('Interested', s.interested, const Color(0xFFB45309)),
              _Stat('🔥 Hot', s.hot, AppColors.hot),
              _Stat('Remaining', s.remaining, AppColors.brand),
            ],
          ),
          if (c.recentCallIds.isNotEmpty) ...[
            const SectionLabel('Latest results'),
            for (final id in c.recentCallIds) _RecentCall(callId: id),
          ],
          if (!running) ...[
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Review follow-ups',
              icon: Icons.chat_rounded,
              color: AppColors.whatsapp,
              onPressed: () => context.go('/followups'),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'View hot leads',
              onPressed: () => context.go('/leads?filter=hot'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      semanticLabel: '$value $label',
      padding: const EdgeInsets.all(12),
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: t.headlineMedium?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCall extends ConsumerWidget {
  const _RecentCall({required this.callId});
  final String callId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider(callId)).value;
    if (call == null) {
      return const SizedBox(
        height: 70,
        child: Center(child: Skeleton(height: 50)),
      );
    }
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push(
          call.status.isConnected
              ? '/calls/${call.id}/result'
              : '/calls/${call.id}',
        ),
        child: Row(
          children: [
            LeadAvatar(
              name: call.leadName,
              temperature:
                  call.leadScore?.temperature ?? LeadTemperature.unknown,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.leadName, style: t.titleSmall),
                  Text(
                    call.status.isConnected
                        ? call.outcome ?? 'Connected'
                        : call.status.label,
                    style: t.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (call.leadScore != null)
              ScoreBadge(score: call.leadScore)
            else
              const Pill(label: 'No answer'),
          ],
        ),
      ),
    );
  }
}

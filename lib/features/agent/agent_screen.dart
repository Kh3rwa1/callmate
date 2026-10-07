import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';

/// AI Employee – "What can my AI employee do?"
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(agentProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<Agent?>(
          value: agent,
          onRetry: () => ref.invalidate(agentProvider),
          data: (a) => a == null
              ? EmptyState(
                  title: 'No AI employee yet',
                  actionLabel: 'Create My AI Employee',
                  onAction: () => context.go('/onboarding'),
                )
              : _Body(agent: a),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final a = agent;
    final active = a.status == AgentStatus.active;
    final usage = ref.watch(usageProvider).value;
    final knowledge = ref.watch(knowledgeProvider).value;
    final caps = a.capabilities.isEmpty ? genericCapabilities : a.capabilities;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 36),
      children: [
        Semantics(
          header: true,
          child: Text('AI Employee', style: t.headlineMedium),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: Column(
            children: [
              EmployeeMascot(
                state: active ? MascotState.welcome : MascotState.thinking,
                size: 190,
                agent: a,
              ),
              const SizedBox(height: 8),
              Text(a.name, style: t.displaySmall),
              Text(
                a.role,
                style: t.titleMedium?.copyWith(color: AppColors.brand),
              ),
              const SizedBox(height: 10),
              StatusDot(
                label: active ? 'Active' : a.status.label,
                color: active ? AppColors.success : AppColors.cold,
                pulse: active,
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Edit AI Employee',
                icon: Icons.tune_rounded,
                onPressed: () => context.push('/agent/edit'),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Talk to ${a.name}',
                icon: Icons.mic_rounded,
                onPressed: () => context.push('/voice-test'),
              ),
            ],
          ),
        ),
        const SectionLabel('Identity'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(
            children: [
              _Kv('Name', a.name),
              _Kv('Role', a.role),
              _Kv('Languages', a.languages.join(' · ')),
              _Kv('Voice', a.voice, last: true),
            ],
          ),
        ),
        const SectionLabel('Personality'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.personalityLabel, style: t.titleMedium),
              const SizedBox(height: 12),
              Semantics(
                label:
                    'Personality: ${(100 - a.formality * 100).round()} percent friendly',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: a.formality,
                          minHeight: 8,
                          backgroundColor: AppColors.warmSoft,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '😊 Friendly',
                            style: t.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Formal 👔',
                            style: t.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Goal'),
        AppCard(
          child: Row(
            children: [
              const IconBubble(
                color: AppColors.successSoft,
                child: Emoji('🎯'),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(a.goal, style: t.titleMedium)),
            ],
          ),
        ),
        const SectionLabel('Capabilities'),
        AppCard(
          child: Column(
            children: [
              for (final c in caps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      const Text('✅', style: TextStyle(fontSize: 17)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          c,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SectionLabel('Business Knowledge'),
        AppCard(
          onTap: () => context.push('/agent/teach'),
          child: Row(
            children: [
              const IconBubble(color: AppColors.brandSoft, child: Emoji('📚')),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Teach Your AI', style: t.titleMedium),
                    Text(
                      knowledge == null
                          ? 'Loading…'
                          : '${knowledge.length} sources · services, pricing, FAQs',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SectionLabel('Plan & usage'),
        AppCard(
          onTap: () => context.push('/usage'),
          child: usage == null
              ? const Skeleton(height: 60)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          usage.subscription.planName.toUpperCase(),
                          style: t.labelSmall?.copyWith(color: AppColors.brand),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${Fmt.number(usage.minutesRemaining)} minutes left',
                      style: t.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: usage.ratio,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(9),
                      backgroundColor: AppColors.brandSoft,
                      color: usage.ratio > 0.85
                          ? AppColors.hot
                          : AppColors.brand,
                    ),
                  ],
                ),
        ),
        const SectionLabel('More'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Callbacks'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/callbacks'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/notifications'),
              ),
              if (AppEnv.showDemoTools) ...[
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Demo controls'),
                  subtitle: const Text(
                    'Simulate calls, hot leads, notifications',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/demo'),
                ),
              ],
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.hot),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: AppColors.hot),
                ),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'You will need to sign in again to access your workspace.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Sign out',
                            style: TextStyle(color: AppColors.hot),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await ref.read(sessionProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.inkFaint,
                ),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: AppColors.inkFaint),
                ),
                subtitle: const Text(
                  'Permanently erase account and data',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete account?'),
                      content: const Text(
                        'This action cannot be undone. All your business records, leads, calls, transcripts, and AI configurations will be permanently deleted.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Delete permanently',
                            style: TextStyle(
                              color: AppColors.hot,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await ref.read(sessionProvider.notifier).deleteAccount();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.last = false});
  final String k;
  final String v;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(k, style: t.bodyMedium)),
          Expanded(child: Text(v, style: t.titleSmall)),
        ],
      ),
    );
  }
}

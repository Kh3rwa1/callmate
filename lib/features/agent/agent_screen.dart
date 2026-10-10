import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

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

  Future<void> _allowAlerts(BuildContext context, WidgetRef ref) async {
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    // Once denied, Android only lets the user re-enable it
    // from system settings.
    if (!granted) {
      await openAppSettings();
    } else if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alerts are on')));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again.'),
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
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This cannot be undone. All leads, calls, transcripts and AI settings will be permanently deleted.',
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
      try {
        await ref.read(sessionProvider.notifier).deleteAccount();
        if (context.mounted) context.go('/login');
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Account not deleted: ${friendlyError(e)}")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final a = agent;
    final usage = ref.watch(usageProvider).value;
    final knowledge = ref.watch(knowledgeProvider).value;
    final caps = a.capabilities.isEmpty ? genericCapabilities : a.capabilities;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 40),
      children: [
        Semantics(
          header: true,
          child: Text('AI Employee', style: t.headlineMedium),
        ),
        const SizedBox(height: 18),
        _Hero(agent: a),
        const SectionLabel('Profile'),
        _Group(
          children: [
            _InfoRow(label: 'Languages', value: a.languages.join(' · ')),
            _InfoRow(label: 'Voice', value: a.voice),
            _InfoRow(label: 'Personality', value: a.personalityLabel),
            _InfoRow(label: 'Goal', value: a.goal, stacked: true),
          ],
        ),
        const SectionLabel('Capabilities'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final c in caps) _CapabilityPill(c)],
        ),
        const SizedBox(height: 28),
        _Group(
          children: [
            _NavRow(
              icon: Icons.menu_book_outlined,
              title: 'Teach Your AI',
              value: knowledge == null ? null : '${knowledge.length} sources',
              onTap: () => context.push('/agent/teach'),
            ),
            usage == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Skeleton(height: 28),
                  )
                : _NavRow(
                    icon: Icons.timelapse_rounded,
                    title: '${Fmt.number(usage.minutesRemaining)} min left',
                    value: usage.subscription.planName,
                    progress: usage.ratio,
                    progressColor: usage.ratio > 0.85
                        ? AppColors.hot
                        : AppColors.ink,
                    onTap: () => context.push('/usage'),
                  ),
          ],
        ),
        const SizedBox(height: 16),
        _Group(
          children: [
            _NavRow(
              icon: Icons.event_outlined,
              title: 'Callbacks',
              onTap: () => context.push('/callbacks'),
            ),
            _NavRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              onTap: () => context.push('/notifications'),
            ),
            _NavRow(
              icon: Icons.notifications_active_outlined,
              title: 'Allow alerts',
              onTap: () => _allowAlerts(context, ref),
            ),
            if (AppEnv.showDemoTools)
              _NavRow(
                icon: Icons.science_outlined,
                title: 'Demo controls',
                onTap: () => context.push('/demo'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Group(
          children: [
            _NavRow(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              color: AppColors.hot,
              chevron: false,
              onTap: () => _signOut(context, ref),
            ),
            _NavRow(
              icon: Icons.delete_outline_rounded,
              title: 'Delete account',
              color: AppColors.inkFaint,
              chevron: false,
              onTap: () => _deleteAccount(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact profile header: mascot, name, role, status and two actions.
class _Hero extends StatelessWidget {
  const _Hero({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = agent;
    final active = a.status == AgentStatus.active;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Row(
            children: [
              EmployeeMascot(
                state: active ? MascotState.welcome : MascotState.thinking,
                size: 88,
                agent: a,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.role,
                      style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    StatusDot(
                      label: active ? 'Active' : a.status.label,
                      color: active ? AppColors.success : AppColors.cold,
                      pulse: active,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Talk to ${a.name}',
                  icon: Icons.mic_rounded,
                  onPressed: () => context.push('/voice-test'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Edit AI Employee',
                onPressed: () => context.push('/agent/edit'),
                icon: const Icon(Icons.tune_rounded),
                style: IconButton.styleFrom(
                  fixedSize: const Size(54, 54),
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.border, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One white card holding rows separated by hairline dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              color: AppColors.border,
            ),
          c,
        ],
      ],
    ),
  );
}

/// Settings-style label/value row. Long values stack under the label.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.stacked = false,
  });
  final String label;
  final String value;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final labelStyle = t.bodyMedium?.copyWith(color: AppColors.inkSoft);
    final valueStyle = t.titleSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                Text(value, style: valueStyle),
              ],
            )
          : Row(
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    style: valueStyle,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Tappable row: icon, title, optional quiet value, chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.color,
    this.chevron = true,
    this.progress,
    this.progressColor = AppColors.ink,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final Color? color;
  final bool chevron;
  final double? progress;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = color ?? AppColors.ink;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: t.titleSmall?.copyWith(color: fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(9),
                          backgroundColor: AppColors.surfaceMuted,
                          color: progressColor,
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    value!,
                    style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
                  ),
                ],
                if (chevron) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.inkFaint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small white pill with a check, used for capabilities.
class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.ink, fontSize: 13),
        ),
      ],
    ),
  );
}

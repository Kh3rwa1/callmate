import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_persona.dart';
import '../../core/widgets/brand_widgets.dart';
import 'owner_test_call_sheet.dart';

/// AI Employee – "What can my AI employee do?" plus the app's settings.
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final agent = ref.watch(agentProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView<Agent?>(
          value: agent,
          onRetry: () => ref.invalidate(agentProvider),
          data: (a) => a == null
              ? EmptyState(
                  title: s.noAgentYet,
                  actionLabel: s.createMyAiEmployee,
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
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    // Once denied, Android only lets the user re-enable it
    // from system settings.
    if (!granted) {
      await openAppSettings();
    } else {
      Haptics.success();
      messenger.showSnackBar(SnackBar(content: Text(s.alertsOn)));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.signOutQ),
        content: Text(s.signInAgainNeeded),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.hot),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.signOut),
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
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAccountQ),
        content: Text(s.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.hot,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              Haptics.warn();
              Navigator.pop(ctx, true);
            },
            child: Text(s.deletePermanently),
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
            SnackBar(content: Text(s.accountNotDeleted(friendlyError(e, s)))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final a = agent;
    final usage = ref.watch(usageProvider).value;
    final knowledge = ref.watch(knowledgeProvider).value;
    final referralBonus = ref.watch(referralsProvider).value?.bonusMinutes;
    final category = ref.watch(businessProvider).value?.category;
    final caps = a.capabilities.isEmpty ? genericCapabilities : a.capabilities;
    final lang = ref.watch(languageProvider);
    final mode = ref.watch(themeModeProvider);

    var i = 0;
    Widget reveal(Widget child) =>
        Reveal(id: 'agent-section-${i++}', index: i, child: child);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 40),
      children: [
        Semantics(
          header: true,
          child: GradientText(s.aiEmployeeTitle, style: t.headlineMedium),
        ),
        const SizedBox(height: 18),
        reveal(_Hero(agent: a)),
        SectionLabel(s.profile),
        reveal(
          CardGroup(
            children: [
              _InfoRow(label: s.languagesLabel, value: s.dataList(a.languages)),
              _InfoRow(
                label: s.voice,
                value: isMaleVoice(a.voice) ? s.obVoiceMale : s.obVoiceFemale,
              ),
              _InfoRow(label: s.personality, value: s.data(a.personalityLabel)),
              _InfoRow(label: s.goal, value: s.data(a.goal), stacked: true),
            ],
          ),
        ),
        SectionLabel(s.capabilities),
        reveal(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (j, c) in caps.indexed)
                PopIn(
                  delay: Duration(milliseconds: 40 * j),
                  child: _CapabilityPill(s.data(c)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        reveal(
          CardGroup(
            children: [
              _NavRow(
                icon: Icons.menu_book_outlined,
                title: s.teachYourAi,
                value: knowledge == null ? null : s.nSources(knowledge.length),
                onTap: () => context.push('/agent/teach'),
              ),
              _NavRow(
                icon: Icons.checklist_rounded,
                title: s.playbookTitle,
                value: category == null
                    ? null
                    : s.playbookName(playbookVerticalFor(category)),
                onTap: () => context.push('/agent/playbook'),
              ),
              usage == null
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Skeleton(height: 28),
                    )
                  : _NavRow(
                      icon: Icons.timelapse_rounded,
                      title: s.minLeft(Fmt.number(usage.minutesRemaining)),
                      value: s.data(usage.subscription.planName),
                      progress: usage.ratio,
                      progressColor: usage.ratio > 0.85
                          ? AppColors.hot
                          : AppColors.brand,
                      onTap: () => context.push('/usage'),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        reveal(
          CardGroup(
            children: [
              _NavRow(
                icon: Icons.ring_volume_outlined,
                title: s.hearYourAiShort,
                onTap: () => showOwnerTestCallSheet(context),
              ),
              _NavRow(
                icon: Icons.card_giftcard_outlined,
                title: s.inviteAndEarn,
                value: referralBonus == null
                    ? null
                    : s.inviteRowValue(referralBonus),
                onTap: () => context.push('/invite'),
              ),
              _NavRow(
                icon: Icons.event_outlined,
                title: s.callbacksTitle,
                onTap: () => context.push('/callbacks'),
              ),
              _NavRow(
                icon: Icons.notifications_none_rounded,
                title: s.notifications,
                onTap: () => context.push('/notifications'),
              ),
              _NavRow(
                icon: Icons.notifications_active_outlined,
                title: s.allowAlerts,
                onTap: () => _allowAlerts(context, ref),
              ),
              const _DigestRow(),
              if (AppEnv.showDemoTools)
                _NavRow(
                  icon: Icons.science_outlined,
                  title: s.demoControls,
                  onTap: () => context.push('/demo'),
                ),
            ],
          ),
        ),
        SectionLabel(s.settings),
        reveal(
          CardGroup(
            children: [
              _NavRow(
                icon: Icons.translate_rounded,
                title: s.appLanguage,
                value: lang?.nativeName ?? s.phoneDefault,
                onTap: () => showLanguageSheet(context, ref),
              ),
              _NavRow(
                icon: Icons.contrast_rounded,
                title: s.appearance,
                value: switch (mode) {
                  ThemeMode.light => s.themeLight,
                  ThemeMode.dark => s.themeDark,
                  ThemeMode.system => s.themeSystem,
                },
                onTap: () => showAppearanceSheet(context, ref),
              ),
              _NavRow(
                icon: Icons.help_outline_rounded,
                title: s.helpSupport,
                onTap: () => showSupportSheet(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        reveal(
          CardGroup(
            children: [
              _NavRow(
                icon: Icons.logout_rounded,
                title: s.signOut,
                color: AppColors.hot,
                chevron: false,
                onTap: () => _signOut(context, ref),
              ),
              _NavRow(
                icon: Icons.delete_outline_rounded,
                title: s.deleteAccount,
                color: AppColors.inkFaint,
                chevron: false,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
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
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final a = agent;
    final active = a.status == AgentStatus.active;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Row(
            children: [
              AgentAvatar(agent: a, size: 80),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.data(a.role),
                      style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    StatusDot(
                      label: s.agentStatus(a.status),
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
                  label: s.talkTo(a.name),
                  icon: Icons.mic_rounded,
                  onPressed: () => context.push('/voice-test'),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                scale: 0.92,
                child: IconButton.outlined(
                  tooltip: s.editAiEmployee,
                  onPressed: () => context.push('/agent/edit'),
                  icon: const Icon(Icons.tune_rounded),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(54, 54),
                    foregroundColor: AppColors.ink,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: AppColors.border, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    style: valueStyle,
                    textAlign: TextAlign.end,
                    maxLines: 2,
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
    this.progressColor,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final Color? color;
  final bool chevron;
  final double? progress;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = color ?? AppColors.ink;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress!),
                          duration: AppMotion.of(context, AppMotion.slow),
                          curve: AppMotion.emphasized,
                          builder: (_, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(9),
                            backgroundColor: AppColors.surfaceMuted,
                            color: progressColor ?? AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
                    ),
                  ),
                ],
                if (chevron) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 7 PM daily summary push on/off (`businesses.digest_enabled`).
class _DigestRow extends ConsumerStatefulWidget {
  const _DigestRow();
  @override
  ConsumerState<_DigestRow> createState() => _DigestRowState();
}

class _DigestRowState extends ConsumerState<_DigestRow> {
  /// Optimistic value while the save is in flight.
  bool? _pending;

  Future<void> _set(Business biz, bool on) async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    Haptics.tap();
    setState(() => _pending = on);
    try {
      await ref
          .read(businessRepoProvider)
          .saveBusiness(biz.copyWith(digestEnabled: on));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final biz = ref.watch(businessProvider).value;
    final on = _pending ?? biz?.digestEnabled ?? true;
    return SwitchListTile(
      value: on,
      onChanged: biz == null || _pending != null ? null : (v) => _set(biz, v),
      secondary: Icon(Icons.summarize_outlined, size: 22, color: AppColors.ink),
      title: Text(s.dailySummaryTitle, style: t.titleSmall),
      subtitle: Text(
        s.dailySummarySubtitle,
        style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

/// Small pill with a check, used for capabilities.
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
        Icon(Icons.check_rounded, size: 16, color: AppColors.success),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.ink,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

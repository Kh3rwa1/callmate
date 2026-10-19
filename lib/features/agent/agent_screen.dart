import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/utils/phone.dart';
import '../../core/settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/whole_word_text.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/world.dart';
import 'owner_test_call_sheet.dart';

/// AI Employee – "What can my AI employee do?" plus the app's settings.
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final agent = ref.watch(agentProvider);
    return Scaffold(
      body: WorldStatusBar(
        world: AppWorld.agent,
        child: SafeArea(
          top: false,
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
    final a = agent;
    final usage = ref.watch(usageProvider).value;
    final knowledge = ref.watch(knowledgeProvider).value;
    final referralBonus = ref.watch(referralsProvider).value?.bonusMinutes;
    final answering = ref.watch(answeringProvider).value;
    final number = ref.watch(businessNumberProvider).value;
    final lang = ref.watch(languageProvider);
    final mode = ref.watch(themeModeProvider);
    final textSize = ref.watch(textSizeProvider);

    var i = 0;
    Widget reveal(Widget child) =>
        Reveal(id: 'agent-section-${i++}', index: i, child: child);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        _Hero(agent: a),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------ Your employee
              _SectionHeader(
                s.sectionYourEmployee,
                key: const Key('section-employee'),
              ),
              reveal(
                CardGroup(
                  children: [
                    _NavRow(
                      icon: Icons.ring_volume_outlined,
                      glyph: AppGlyphs.call,
                      title: s.hearYourAiShort,
                      onTap: () => showOwnerTestCallSheet(context),
                    ),
                    if (number != null && number.available)
                      _NavRow(
                        key: const Key('agent-business-number'),
                        icon: Icons.phone_in_talk_outlined,
                        title: s.businessNumberTitle,
                        value: number.number != null
                            ? PhoneUtils.display(number.number!.phone)
                            : s.premiumBadge,
                        onTap: () => context.push('/agent/number'),
                      ),
                    _NavRow(
                      icon: Icons.menu_book_outlined,
                      glyph: AppGlyphs.teach,
                      title: s.teachYourAi,
                      value: knowledge == null
                          ? null
                          : s.nSources(knowledge.length),
                      onTap: () => context.push('/agent/teach'),
                    ),
                    _NavRow(
                      icon: Icons.checklist_rounded,
                      title: s.playbookTitle,
                      onTap: () => context.push('/agent/playbook'),
                    ),
                    _NavRow(
                      key: const Key('agent-edit'),
                      icon: Icons.tune_rounded,
                      title: s.editAiEmployee,
                      onTap: () => context.push('/agent/edit'),
                    ),
                  ],
                ),
              ),

              // ----------------------------------------------- Plan & minutes
              _SectionHeader(s.sectionPlan, key: const Key('section-plan')),
              reveal(
                CardGroup(
                  children: [
                    usage == null
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Skeleton(height: 28),
                          )
                        : _NavRow(
                            icon: Icons.timelapse_rounded,
                            glyph: AppGlyphs.plan,
                            title: s.minLeft(
                              Fmt.number(usage.minutesRemaining),
                            ),
                            value: s.planDisplayName(
                              usage.subscription.planName,
                            ),
                            progress: usage.ratio,
                            progressColor: usage.ratio > 0.85
                                ? AppColors.hot
                                : AppColors.brand,
                            onTap: () => context.push('/usage'),
                          ),
                    _NavRow(
                      icon: Icons.card_giftcard_outlined,
                      glyph: AppGlyphs.share,
                      title: s.inviteAndEarn,
                      value: referralBonus == null
                          ? null
                          : s.inviteRowValue(referralBonus),
                      onTap: () => context.push('/invite'),
                    ),
                  ],
                ),
              ),

              // ---------------------------------------------- Settings & help
              _SectionHeader(
                s.sectionSettingsHelp,
                key: const Key('section-settings'),
              ),
              reveal(
                CardGroup(
                  children: [
                    if (answering != null &&
                        (answering.available || answering.enabled))
                      _NavRow(
                        key: const Key('agent-answering'),
                        icon: Icons.phone_callback_outlined,
                        title: s.answeringTitle,
                        value: answering.hasNumber
                            ? s.answerModeShort(answering.mode)
                            : null,
                        onTap: () => context.push('/agent/answering'),
                      ),
                    _NavRow(
                      icon: Icons.notifications_active_outlined,
                      title: s.allowAlerts,
                      onTap: () => _allowAlerts(context, ref),
                    ),
                    const _DigestRow(),
                    _NavRow(
                      icon: Icons.translate_rounded,
                      title: s.appLanguage,
                      value: lang?.nativeName ?? s.phoneDefault,
                      onTap: () => showLanguageSheet(context, ref),
                    ),
                    _NavRow(
                      key: const Key('text-size-row'),
                      icon: Icons.format_size_rounded,
                      title: s.textSize,
                      value: switch (textSize) {
                        TextSize.normal => s.textNormal,
                        TextSize.large => s.textLarge,
                        TextSize.extraLarge => s.textExtraLarge,
                      },
                      onTap: () => showTextSizeSheet(context, ref),
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
                    if (AppEnv.showDemoTools)
                      _NavRow(
                        icon: Icons.science_outlined,
                        title: s.demoControls,
                        onTap: () => context.push('/demo'),
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
          ),
        ),
      ],
    );
  }
}

/// A big serif section heading ("Your employee", "Plan & minutes", …).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 32, 4, 12),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppTheme.serif(27, color: AppColors.ink, height: 1.1),
      ),
    ),
  );
}

/// The marigold world at the top of the tab: the employee's name set big
/// like a name badge, their role and status, and two actions.
class _Hero extends StatelessWidget {
  const _Hero({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final a = agent;
    final active = a.status == AgentStatus.active;
    const world = AppWorld.agent;
    return WorldHeader(
      world: world,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        s.myEmployee,
                        style: AppTheme.eyebrow(color: world.soft),
                      ),
                    ),
                    const SizedBox(height: 8),
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Text(
                        a.name,
                        style: AppTheme.serif(
                          68,
                          color: world.fg,
                          height: 0.95,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.data(a.role),
                      style: t.bodyLarge?.copyWith(
                        color: world.soft,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: world.fg.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: StatusDot(
                        label: s.agentStatus(a.status),
                        color: active
                            ? const Color(0xFF137336)
                            : AppPalette.light.cold,
                        textColor: world.fg,
                        pulse: active,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Mascot(
                state: active ? MascotState.waving : MascotState.resting,
                size: 112,
                haloColor: Colors.white.withValues(alpha: 0.35),
                semanticLabel: a.name,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          // One button; editing lives in "Edit AI Employee" just below.
          WorldButton(
            world: world,
            label: s.talkTo(a.name),
            iconWidget: const Icon(Icons.mic_rounded),
            onPressed: () => context.push('/voice-test'),
          ),
        ],
      ),
    );
  }
}

/// Tappable row: icon, title, optional quiet value, chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.glyph,
    this.value,
    this.color,
    this.chevron = true,
    this.progress,
    this.progressColor,
  });
  final IconData icon;

  /// CallPilot's own icon, used instead of [icon] when given.
  final AppGlyphs? glyph;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final Color? color;
  final bool chevron;
  final double? progress;
  final Color? progressColor;

  /// Above this text scale the value moves under the title instead of
  /// being squeezed (and cut off) beside it.
  static const stackAbove = 1.3;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = color ?? AppColors.ink;
    final stacked =
        MediaQuery.textScalerOf(context).scale(100) / 100 > stackAbove;
    final valueStyle = t.bodyMedium?.copyWith(color: AppColors.inkFaint);
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
                if (glyph case final g?)
                  AppGlyph(g, size: 22, color: fg)
                else
                  Icon(icon, size: 22, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WholeWordText(
                        keepNumbersTogether(title),
                        style: t.titleSmall?.copyWith(color: fg),
                        maxLines: stacked ? 3 : 2,
                      ),
                      if (stacked && value != null)
                        Text(
                          keepNumbersTogether(value!),
                          key: const Key('nav-row-value'),
                          style: valueStyle,
                        ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress!),
                          duration: AppMotion.of(context, AppMotion.slow),
                          curve: AppMotion.emphasized,
                          // The row's title already says what is left; the bar
                          // alone would be read out as a bare "64".
                          builder: (_, v, _) => ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(9),
                              backgroundColor: AppColors.surfaceMuted,
                              color: progressColor ?? AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null && !stacked) ...[
                  const SizedBox(width: 12),
                  // The title keeps most of the row (no two-line titles);
                  // the quiet value gets at most 30% and ellipsizes.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.3,
                    ),
                    child: Text(
                      keepNumbersTogether(value!),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
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

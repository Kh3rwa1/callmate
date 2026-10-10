import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../config/app_env.dart';
import '../motion/motion.dart';
import '../settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';

/// Language picker: phone default, English, हिन्दी, বাংলা. Each option is
/// written in its own language so anyone can find theirs.
Future<void> showLanguageSheet(BuildContext context, WidgetRef ref) {
  final s = context.s;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final current = ref.read(languageProvider);
      final options = <(AppLang?, String)>[
        (null, s.phoneDefault),
        for (final l in AppLang.values) (l, l.nativeName),
      ];
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.appLanguage, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (i, (lang, label)) in options.indexed)
                Reveal(
                  index: i,
                  offset: 8,
                  child: _ChoiceRow(
                    label: label,
                    selected: current == lang,
                    onTap: () {
                      Haptics.tap();
                      ref.read(languageProvider.notifier).set(lang);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Appearance picker: follow the phone, light or dark.
Future<void> showAppearanceSheet(BuildContext context, WidgetRef ref) {
  final s = context.s;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final current = ref.read(themeModeProvider);
      final options = [
        (
          ThemeMode.system,
          s.themeSystem,
          s.themeSystemHint,
          Icons.brightness_auto_rounded,
        ),
        (ThemeMode.light, s.themeLight, null, Icons.light_mode_outlined),
        (ThemeMode.dark, s.themeDark, null, Icons.dark_mode_outlined),
      ];
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.appearance, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (i, (mode, label, hint, icon)) in options.indexed)
                Reveal(
                  index: i,
                  offset: 8,
                  child: _ChoiceRow(
                    label: label,
                    hint: hint,
                    icon: icon,
                    selected: current == mode,
                    onTap: () {
                      Haptics.tap();
                      ref.read(themeModeProvider.notifier).set(mode);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Help & support: email the team and read the legal pages. Links whose URL
/// is not configured for this build are hidden.
Future<void> showSupportSheet(BuildContext context) {
  final s = context.s;
  final options = <(String, String?, IconData, Uri)>[
    (
      s.emailSupport,
      AppEnv.supportEmail,
      Icons.mail_outline_rounded,
      Uri(
        scheme: 'mailto',
        path: AppEnv.supportEmail,
        query: 'subject=${Uri.encodeComponent(s.supportEmailSubject)}',
      ),
    ),
    if (AppEnv.privacyUrl.isNotEmpty)
      (
        s.privacyPolicy,
        null,
        Icons.privacy_tip_outlined,
        Uri.parse(AppEnv.privacyUrl),
      ),
    if (AppEnv.termsUrl.isNotEmpty)
      (
        s.termsOfService,
        null,
        Icons.description_outlined,
        Uri.parse(AppEnv.termsUrl),
      ),
    if (AppEnv.deleteAccountUrl.isNotEmpty)
      (
        s.deleteAccountHelp,
        null,
        Icons.person_remove_outlined,
        Uri.parse(AppEnv.deleteAccountUrl),
      ),
  ];
  return _showLinkSheet(context, s.helpSupport, options);
}

/// The options on the Help sheet for [s]'s language: the 1-minute video
/// only when configured for this build, email always.
List<(String, String?, IconData, Uri)> helpOptions(S s) {
  final video = AppEnv.helpVideoUrl(s.lang.code);
  return [
    if (video != null)
      (
        s.helpWatchVideo,
        null,
        Icons.play_circle_outline_rounded,
        Uri.parse(video),
      ),
    (
      s.helpEmail,
      AppEnv.supportEmail,
      Icons.mail_outline_rounded,
      Uri(
        scheme: 'mailto',
        path: AppEnv.supportEmail,
        query: 'subject=${Uri.encodeComponent(s.supportEmailSubject)}',
      ),
    ),
  ];
}

/// "Help" from the Home top bar: a 1-minute video and email.
Future<void> showHelpSheet(BuildContext context) =>
    _showLinkSheet(context, context.s.help, helpOptions(context.s));

/// "Text size": Normal / Large / Extra large, on top of the phone's size.
Future<void> showTextSizeSheet(BuildContext context, WidgetRef ref) {
  final s = context.s;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) {
      final current = ref.read(textSizeProvider);
      final options = [
        (TextSize.normal, s.textNormal),
        (TextSize.large, s.textLarge),
        (TextSize.extraLarge, s.textExtraLarge),
      ];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            0,
            AppSpace.page,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.textSize, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (i, (size, label)) in options.indexed)
                Reveal(
                  index: i,
                  offset: 8,
                  child: _ChoiceRow(
                    label: label,
                    icon: Icons.format_size_rounded,
                    selected: current == size,
                    onTap: () {
                      Haptics.tap();
                      ref.read(textSizeProvider.notifier).set(size);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A sheet of rows that each open a link. Errors stay inside the sheet: a
/// snackbar would render behind it.
Future<void> _showLinkSheet(
  BuildContext context,
  String title,
  List<(String, String?, IconData, Uri)> options,
) {
  final s = context.s;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              0,
              AppSpace.page,
              16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final (i, (label, hint, icon, uri)) in options.indexed)
                  Reveal(
                    index: i,
                    offset: 8,
                    child: _ChoiceRow(
                      label: label,
                      hint: hint,
                      icon: icon,
                      selected: false,
                      onTap: () async {
                        Haptics.tap();
                        var ok = false;
                        try {
                          ok = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                        if (!ok && ctx.mounted) {
                          setSheetState(() => error = s.couldNotOpen(label));
                        }
                      },
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      error!,
                      key: const Key('link-sheet-error'),
                      style: Theme.of(
                        ctx,
                      ).textTheme.bodyLarge?.copyWith(color: AppColors.hot),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hint,
    this.icon,
  });
  final String label;
  final String? hint;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: AppCard(
          onTap: onTap,
          shadow: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.6 : 1.2,
          ),
          color: selected ? AppColors.brandSoft : AppColors.surface,
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 21,
                  color: selected ? AppColors.brand : AppColors.inkSoft,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.titleSmall),
                    if (hint != null) Text(hint!, style: t.bodyMedium),
                  ],
                ),
              ),
              PopSwitcher(
                child: selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('on'),
                        color: AppColors.brand,
                        size: 22,
                      )
                    : const SizedBox(key: ValueKey('off'), width: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "🌐 English" pill that opens the language picker. Lives on the
/// first screens a new owner sees (sign-in, welcome), before Settings.
class LanguageChip extends ConsumerWidget {
  const LanguageChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    ref.watch(languageProvider);
    return Semantics(
      button: true,
      label: s.appLanguage,
      excludeSemantics: true,
      child: Pressable(
        scale: 0.94,
        onTap: () => showLanguageSheet(context, ref),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.translate_rounded, size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              SwapFade(
                child: Text(
                  s.lang.nativeName,
                  key: ValueKey(s.lang),
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

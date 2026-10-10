import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
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
                    if (hint != null) Text(hint!, style: t.bodySmall),
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
                  style: Theme.of(context).textTheme.labelLarge,
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

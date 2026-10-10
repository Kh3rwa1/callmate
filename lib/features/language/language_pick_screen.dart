import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../splash/splash_screen.dart';

/// First launch: before a single word of English, the owner picks his
/// language with one tap. Written in all three languages at once, so it
/// reads right whatever the phone is set to.
class LanguagePickScreen extends ConsumerWidget {
  const LanguagePickScreen({super.key});

  /// Hindi first: most owners we call for read it. The phone's own language
  /// gets a small "phone" mark so it's easy to spot.
  static const _order = [AppLang.hi, AppLang.bn, AppLang.en];

  static const _hint = {
    AppLang.hi: 'हिन्दी में चलाएँ',
    AppLang.bn: 'বাংলায় চালান',
    AppLang.en: 'Use in English',
  };

  Future<void> _pick(BuildContext context, WidgetRef ref, AppLang lang) async {
    Haptics.success();
    await ref.read(languageProvider.notifier).set(lang);
    if (context.mounted) await goAfterLaunch(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final phone = AppLang.fromCode(
      View.of(context).platformDispatcher.locale.languageCode,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.lg,
              AppSpace.page,
              AppSpace.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 56),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: PopIn(
                      child: FloatIdle(
                        child: Mascot(
                          state: MascotState.waving,
                          size: (c.maxHeight * 0.22).clamp(120, 170),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Reveal(
                    index: 2,
                    child: Semantics(
                      header: true,
                      child: Column(
                        children: [
                          Text(
                            'अपनी भाषा चुनें',
                            textAlign: TextAlign.center,
                            style: t.headlineSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'আপনার ভাষা বেছে নিন  ·  Choose your language',
                            textAlign: TextAlign.center,
                            style: t.titleSmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  for (final (i, lang) in _order.indexed) ...[
                    Reveal(
                      index: 4 + i,
                      child: _LangCard(
                        name: lang.nativeName,
                        hint: _hint[lang]!,
                        isPhone: lang == phone,
                        onTap: () => _pick(context, ref, lang),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    required this.name,
    required this.hint,
    required this.isPhone,
    required this.onTap,
  });
  final String name;
  final String hint;
  final bool isPhone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$name. $hint',
      child: ExcludeSemantics(
        child: Pressable(
          haptic: false,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPhone ? AppColors.brand : AppColors.border,
                width: isPhone ? 2 : 1,
              ),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                if (isPhone) ...[
                  Icon(
                    Icons.smartphone_rounded,
                    size: 20,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/file_pick.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../knowledge/knowledge_sheets.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ========================================================== 5. Teach AI
class TeachAiOnboardingScreen extends ConsumerWidget {
  const TeachAiOnboardingScreen({super.key});

  Future<void> _pickPdf(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    void tell(String message) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    try {
      final f = await pickSingleFile(
        extensions: ['pdf'],
        maxBytes: 15 * 1024 * 1024,
      );
      if (f == null) return;
      ref
          .read(onboardingProvider.notifier)
          .addKnowledge(
            KnowledgeInput(
              type: KnowledgeType.pdf,
              title: f.name.replaceAll(
                RegExp(r'\.pdf$', caseSensitive: false),
                '',
              ),
              fileName: f.name,
              bytes: f.bytes,
            ),
          );
    } on FileTooLargeException {
      tell(s.pdfTooLarge);
    } catch (_) {
      tell(s.pdfUnreadable);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final n = ref.read(onboardingProvider.notifier);

    Future<void> add(KnowledgeType type) async {
      if (type == KnowledgeType.pdf) return _pickPdf(context, ref);
      final input = await showKnowledgeInputSheet(context, type);
      if (input != null) n.addKnowledge(input);
    }

    final options = <(KnowledgeType, String)>[
      (KnowledgeType.pdf, s.uploadPdf),
      (KnowledgeType.website, s.addWebsite),
      (KnowledgeType.faq, s.addFaq),
      (KnowledgeType.businessInfo, s.addBusinessInfo),
      (KnowledgeType.text, s.pasteText),
    ];

    return OnboardingScaffold(
      step: 5,
      title: s.teachYourAi,
      subtitle: s.obTeachSub,
      revealChildren: false,
      cta: SwapFade(
        child: d.knowledge.isEmpty
            ? SizedBox(
                key: const ValueKey('skip'),
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => context.push('/onboarding/create'),
                  child: Text(s.obSkipForNow),
                ),
              )
            : PrimaryButton(
                key: const ValueKey('continue'),
                label: s.continueLabel,
                trailingArrow: true,
                onPressed: () => context.push('/onboarding/create'),
              ),
      ),
      children: [
        CardGroup(
          indent: 68,
          children: [
            for (final (i, (type, title)) in options.indexed)
              Reveal(
                index: 2 + i,
                offset: 10,
                child: _TeachOption(
                  icon: AppIcons.knowledge(type),
                  title: title,
                  onTap: () => add(type),
                ),
              ),
          ],
        ),
        // Added sources slide open below; each lands with a drawn tick.
        AnimatedSize(
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: d.knowledge.isEmpty
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(
                      s.obAdded,
                      trailing: AnimatedCount(
                        value: d.knowledge.length,
                        style: t.labelLarge?.copyWith(
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                    CardGroup(
                      indent: 50,
                      children: [
                        for (final k in d.knowledge)
                          PopIn(
                            key: ObjectKey(k),
                            child: _AddedRow(
                              title: k.title,
                              removeLabel: s.remove,
                              onRemove: () => n.removeKnowledge(k),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Reveal(
          index: 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.upload_file_rounded,
                size: 18,
                color: AppColors.inkFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.obCsvLater,
                  style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeachOption extends StatelessWidget {
  const _TeachOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: Pressable(
        scale: 0.98,
        child: InkWell(
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconBubble(
                    size: 38,
                    color: AppColors.surfaceMuted,
                    child: Icon(icon, size: 20, color: AppColors.ink),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(title, style: t.titleSmall)),
                  Icon(Icons.add_rounded, size: 22, color: AppColors.brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddedRow extends StatelessWidget {
  const _AddedRow({
    required this.title,
    required this.removeLabel,
    required this.onRemove,
  });
  final String title;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          SuccessCheck(size: 22, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: t.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: removeLabel,
            onPressed: () {
              Haptics.tap();
              onRemove();
            },
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

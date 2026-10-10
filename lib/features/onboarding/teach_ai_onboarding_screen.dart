import '../../core/utils/file_pick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/models.dart';
import '../knowledge/knowledge_sheets.dart';
import 'onboarding_controller.dart';
import 'onboarding_scaffold.dart';

// ========================================================== 5. Teach AI
class TeachAiOnboardingScreen extends ConsumerWidget {
  const TeachAiOnboardingScreen({super.key});

  Future<void> _pickPdf(BuildContext context, WidgetRef ref) async {
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
              title: f.name.replaceAll('.pdf', ''),
              fileName: f.name,
              bytes: f.bytes,
            ),
          );
    } on FileTooLargeException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That PDF is over 15 MB. Try a smaller file.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t open that file. Try another PDF.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(onboardingProvider);
    final t = Theme.of(context).textTheme;
    final n = ref.read(onboardingProvider.notifier);

    Future<void> add(KnowledgeType type) async {
      if (type == KnowledgeType.pdf) return _pickPdf(context, ref);
      final input = await showKnowledgeInputSheet(context, type);
      if (input != null) n.addKnowledge(input);
    }

    return OnboardingScaffold(
      step: 5,
      title: 'Teach your AI',
      cta: d.knowledge.isEmpty
          ? SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => context.push('/onboarding/create'),
                child: const Text('Skip for now'),
              ),
            )
          : PrimaryButton(
              label: 'Continue',
              onPressed: () => context.push('/onboarding/create'),
            ),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              _TeachOption(
                emoji: '📄',
                title: 'Upload brochure PDF',
                onTap: () => add(KnowledgeType.pdf),
              ),
              _TeachOption(
                emoji: '🌐',
                title: 'Add website',
                onTap: () => add(KnowledgeType.website),
              ),
              _TeachOption(
                emoji: '❓',
                title: 'Add FAQ',
                onTap: () => add(KnowledgeType.faq),
              ),
              _TeachOption(
                emoji: '📍',
                title: 'Add business information',
                onTap: () => add(KnowledgeType.businessInfo),
              ),
              _TeachOption(
                emoji: '📝',
                title: 'Paste text',
                last: true,
                onTap: () => add(KnowledgeType.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TeachOption(
          emoji: '📥',
          title: 'Import CSV leads later',
          last: true,
          trailing: Text(
            'Later',
            style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
          ),
          onTap: () => ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'You\'ll be able to import leads right after setup.',
                ),
              ),
            ),
        ),
        if (d.knowledge.isNotEmpty) ...[
          const SectionLabel('Added'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (i, k) in d.knowledge.indexed)
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    decoration: BoxDecoration(
                      border: i == d.knowledge.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(color: AppColors.hairline),
                            ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            k.title,
                            style: t.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => n.removeKnowledge(k),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TeachOption extends StatelessWidget {
  const _TeachOption({
    required this.emoji,
    required this.title,
    required this.onTap,
    this.trailing,
    this.last = false,
  });
  final String emoji;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              IconBubble(
                size: 38,
                color: AppColors.surfaceMuted,
                child: Emoji(emoji, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: t.titleSmall)),
              trailing ??
                  const Icon(
                    Icons.add_rounded,
                    size: 22,
                    color: AppColors.inkFaint,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      title: 'Teach Your AI',
      subtitle:
          'The more your AI employee knows, the better it answers. You can always add more later.',
      cta: PrimaryButton(
        label: d.knowledge.isEmpty ? 'Skip for now' : 'Continue',
        onPressed: () => context.push('/onboarding/create'),
      ),
      children: [
        _TeachOption(
          emoji: '📄',
          title: 'Upload brochure PDF',
          subtitle: 'Services, pricing, brochure',
          onTap: () => add(KnowledgeType.pdf),
        ),
        _TeachOption(
          emoji: '🌐',
          title: 'Add website',
          subtitle: 'We\'ll read your public pages',
          onTap: () => add(KnowledgeType.website),
        ),
        _TeachOption(
          emoji: '❓',
          title: 'Add FAQ',
          subtitle: 'Common questions customers ask',
          onTap: () => add(KnowledgeType.faq),
        ),
        _TeachOption(
          emoji: '📍',
          title: 'Add business information',
          subtitle: 'Opening hours, location, policies',
          onTap: () => add(KnowledgeType.businessInfo),
        ),
        _TeachOption(
          emoji: '📝',
          title: 'Paste text',
          subtitle: 'Services, pricing, offers – anything else',
          onTap: () => add(KnowledgeType.text),
        ),
        _TeachOption(
          emoji: '📥',
          title: 'Import CSV leads later',
          subtitle: 'You can add leads from the Leads tab',
          trailing: const Pill(label: 'Later'),
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
          for (final k in d.knowledge)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                shadow: false,
                border: Border.all(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        k.title,
                        style: t.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => n.removeKnowledge(k),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
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
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconBubble(color: AppColors.surfaceMuted, child: Emoji(emoji)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.add_rounded, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}

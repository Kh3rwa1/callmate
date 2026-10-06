import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import 'knowledge_sheets.dart';

class TeachAiScreen extends ConsumerStatefulWidget {
  const TeachAiScreen({super.key});
  @override
  ConsumerState<TeachAiScreen> createState() => _TeachAiScreenState();
}

class _TeachAiScreenState extends ConsumerState<TeachAiScreen> {
  final Map<String, KnowledgeSource> _inFlight = {};

  Future<void> _add(KnowledgeType type) async {
    KnowledgeInput? input;
    if (type == KnowledgeType.pdf) {
      try {
        final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
        final f = r?.files.firstOrNull;
        if (f == null) return;
        if (f.size > 15 * 1024 * 1024) {
          _snack('That PDF is over 15 MB. Try a smaller file.');
          return;
        }
        input = KnowledgeInput(
          type: KnowledgeType.pdf,
          title: f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
          fileName: f.name,
          bytes: f.bytes,
        );
      } catch (_) {
        _snack('Couldn\'t open that file. Try another PDF.');
        return;
      }
    } else {
      if (!mounted) return;
      input = await showKnowledgeInputSheet(context, type);
    }
    if (input == null) return;
    final key = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    ref
        .read(knowledgeRepoProvider)
        .add(input)
        .listen(
          (s) {
            if (!mounted) return;
            setState(() => _inFlight[key] = s);
            if (s.status == KnowledgeStatus.ready) {
              setState(() => _inFlight.remove(key));
              _snack('${ref.read(employeeNameProvider)} learned “${s.title}” ✓');
            }
          },
          onError: (_) {
            if (!mounted) return;
            final cur = _inFlight[key];
            if (cur != null) setState(() => _inFlight[key] = cur.copyWith(status: KnowledgeStatus.failed));
          },
        );
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _openAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add information', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 16),
              for (final (type, emoji, label) in const [
                (KnowledgeType.pdf, '📄', 'Upload PDF'),
                (KnowledgeType.website, '🌐', 'Add website'),
                (KnowledgeType.text, '📝', 'Paste text'),
                (KnowledgeType.faq, '❓', 'Add FAQ'),
              ])
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  minTileHeight: 60,
                  leading: IconBubble(color: Colors.white, size: 44, child: Emoji(emoji)),
                  title: Text(label, style: Theme.of(ctx).textTheme.titleSmall),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _add(type);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _emoji(KnowledgeType t) => switch (t) {
    KnowledgeType.pdf => '📄',
    KnowledgeType.website => '🌐',
    KnowledgeType.faq => '❓',
    KnowledgeType.businessInfo => '📍',
    KnowledgeType.text => '📝',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = ref.watch(knowledgeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Teach Your AI')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add information', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: AsyncView<List<KnowledgeSource>>(
        value: k,
        onRetry: () => ref.invalidate(knowledgeProvider),
        data: (items) {
          final latest = items.isEmpty ? null : items.map((e) => e.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
          final all = [..._inFlight.values, ...items];
          if (all.isEmpty) {
            return EmptyState(
              title: 'Your AI employee hasn\'t learned anything yet',
              message: 'Add services, pricing, FAQs or business details so it can answer customer questions.',
              actionLabel: '+ Add information',
              onAction: _openAddSheet,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(knowledgeProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 100),
              children: [
                Text(
                  'Everything ${ref.watch(employeeNameProvider)} knows about your business – services, pricing, opening hours, location, policies and FAQs.',
                  style: t.bodyMedium,
                ),
                if (latest != null) ...[
                  const SizedBox(height: 8),
                  Text('Last updated ${Fmt.relative(latest)}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                for (final s in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SourceTile(
                      source: s,
                      emoji: _emoji(s.type),
                      onRemove: s.status == KnowledgeStatus.ready && items.contains(s)
                          ? () async {
                              await ref.read(knowledgeRepoProvider).remove(s.id);
                              _snack('Removed “${s.title}”');
                            }
                          : s.status == KnowledgeStatus.failed
                          ? () => setState(() => _inFlight.removeWhere((_, v) => v == s))
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.emoji, this.onRemove});
  final KnowledgeSource source;
  final String emoji;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = source;
    final (label, color) = switch (s.status) {
      KnowledgeStatus.uploading => ('Uploading ${(s.progress * 100).round()}%', AppColors.info),
      KnowledgeStatus.processing => ('Learning…', AppColors.warm),
      KnowledgeStatus.ready => ('Learned', AppColors.success),
      KnowledgeStatus.failed => ('Couldn\'t read this – try again', AppColors.hot),
    };
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconBubble(color: AppColors.surfaceMuted, child: Emoji(emoji)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: t.titleSmall, overflow: TextOverflow.ellipsis),
                    if (s.detail != null) Text(s.detail!, style: t.bodySmall, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (s.status == KnowledgeStatus.ready) const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.success),
                        if (s.status == KnowledgeStatus.failed) const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.hot),
                        if (s.status == KnowledgeStatus.ready || s.status == KnowledgeStatus.failed) const SizedBox(width: 4),
                        Text(label, style: t.labelMedium?.copyWith(color: color)),
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, color: AppColors.inkFaint),
                ),
            ],
          ),
          if (s.status == KnowledgeStatus.uploading || s.status == KnowledgeStatus.processing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: s.status == KnowledgeStatus.uploading ? s.progress : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(9),
              backgroundColor: AppColors.surfaceMuted,
            ),
          ],
        ],
      ),
    );
  }
}

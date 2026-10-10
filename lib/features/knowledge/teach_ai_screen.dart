import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_pick.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import 'knowledge_sheets.dart';

class TeachAiScreen extends ConsumerStatefulWidget {
  const TeachAiScreen({super.key});
  @override
  ConsumerState<TeachAiScreen> createState() => _TeachAiScreenState();
}

class _TeachAiScreenState extends ConsumerState<TeachAiScreen> {
  final Map<String, KnowledgeSource> _inFlight = {};
  Timer? _pollTimer;

  void _checkProcessingPoll(List<KnowledgeSource> items) {
    final hasProcessing = items.any(
      (e) => e.status == KnowledgeStatus.processing,
    );
    if (hasProcessing && (_pollTimer == null || !_pollTimer!.isActive)) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!mounted) return;
        final current = ref.read(knowledgeProvider).asData?.value ?? [];
        final processing = current
            .where((e) => e.status == KnowledgeStatus.processing)
            .toList();
        if (processing.isEmpty) {
          _pollTimer?.cancel();
          _pollTimer = null;
          return;
        }
        for (final item in processing) {
          try {
            await ref.read(knowledgeRepoProvider).get(item.id);
          } catch (_) {}
        }
        ref.invalidate(knowledgeProvider);
      });
    } else if (!hasProcessing && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _add(KnowledgeType type) async {
    final s = context.s;
    KnowledgeInput? input;
    if (type == KnowledgeType.pdf) {
      try {
        final f = await pickSingleFile(
          extensions: ['pdf'],
          maxBytes: 15 * 1024 * 1024,
        );
        if (f == null) return;
        input = KnowledgeInput(
          type: KnowledgeType.pdf,
          title: f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
          fileName: f.name,
          bytes: f.bytes,
        );
      } on FileTooLargeException {
        _snack(s.pdfTooLarge);
        return;
      } catch (_) {
        _snack(s.pdfUnreadable);
        return;
      }
    } else {
      if (!mounted) return;
      input = await showKnowledgeInputSheet(context, type);
    }
    if (input == null) return;
    final key = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final strings = s;
    ref
        .read(knowledgeRepoProvider)
        .add(input)
        .listen(
          (s) {
            if (!mounted) return;
            setState(() => _inFlight[key] = s);
            if (s.status == KnowledgeStatus.ready) {
              setState(() => _inFlight.remove(key));
              ref.invalidate(knowledgeProvider);
              Haptics.success();
              _snack(strings.learned(ref.read(employeeNameProvider), s.title));
            }
          },
          onError: (_) {
            if (!mounted) return;
            final cur = _inFlight[key];
            if (cur != null) {
              setState(
                () => _inFlight[key] = cur.copyWith(
                  status: KnowledgeStatus.failed,
                ),
              );
            }
          },
        );
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _openAddSheet() {
    final s = context.s;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            0,
            AppSpace.page,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  s.addInformation,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              for (final (i, (type, label)) in [
                (KnowledgeType.pdf, s.uploadPdf),
                (KnowledgeType.website, s.addWebsite),
                (KnowledgeType.text, s.pasteText),
                (KnowledgeType.faq, s.addFaq),
              ].indexed)
                Reveal(
                  index: i,
                  offset: 8,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    minTileHeight: 56,
                    leading: IconBubble(
                      color: AppColors.surfaceMuted,
                      size: 40,
                      child: Icon(
                        AppIcons.knowledge(type),
                        size: 20,
                        color: AppColors.ink,
                      ),
                    ),
                    title: Text(
                      label,
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkFaint,
                    ),
                    onTap: () {
                      Haptics.tap();
                      Navigator.pop(ctx);
                      _add(type);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(KnowledgeSource src) async {
    final s = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.removeSourceQ(src.title)),
        content: Text(s.removeSourceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.hot),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(knowledgeRepoProvider).remove(src.id);
    if (mounted) _snack(s.removedSource(src.title));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final k = ref.watch(knowledgeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.teachYourAi)),
      floatingActionButton: PopIn(
        delay: const Duration(milliseconds: 200),
        child: FloatingActionButton.extended(
          onPressed: () {
            Haptics.press();
            _openAddSheet();
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(s.addInformation),
        ),
      ),
      body: AsyncView<List<KnowledgeSource>>(
        value: k,
        onRetry: () => ref.invalidate(knowledgeProvider),
        data: (items) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkProcessingPoll(items);
          });
          final latest = items.isEmpty
              ? null
              : items
                    .map((e) => e.updatedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b);
          final all = [..._inFlight.values, ...items];
          if (all.isEmpty) {
            return EmptyState(
              title: s.nothingLearnedYet,
              message: s.addServicesPricingFaqs,
              actionLabel: s.plusAddInformation,
              onAction: _openAddSheet,
            );
          }
          return RefreshIndicator(
            color: AppColors.brand,
            backgroundColor: AppColors.surface,
            onRefresh: () async => ref.invalidate(knowledgeProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                8,
                AppSpace.page,
                100,
              ),
              children: [
                if (latest != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
                    child: Text(
                      s.lastUpdated(s.relative(latest)),
                      style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                    ),
                  ),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AnimatedSize(
                    duration: AppMotion.of(context, AppMotion.base),
                    curve: AppMotion.standard,
                    alignment: Alignment.topCenter,
                    child: Column(
                      children: [
                        for (final (i, src) in all.indexed) ...[
                          if (i > 0)
                            const Divider(height: 1, thickness: 1, indent: 70),
                          Reveal(
                            key: ValueKey('ks-${src.id}'),
                            id: 'ks-${src.id}',
                            index: i < 8 ? i : 0,
                            child: _SourceTile(
                              source: src,
                              onRemove:
                                  src.status == KnowledgeStatus.ready &&
                                      items.contains(src)
                                  ? () => _remove(src)
                                  : src.status == KnowledgeStatus.failed
                                  ? () => setState(
                                      () => _inFlight.removeWhere(
                                        (_, v) => v == src,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
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
  const _SourceTile({required this.source, this.onRemove});
  final KnowledgeSource source;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final t = Theme.of(context).textTheme;
    final s = source;
    final (label, color) = switch (s.status) {
      KnowledgeStatus.uploading => (
        strings.uploadingPct((s.progress * 100).round()),
        AppColors.info,
      ),
      KnowledgeStatus.processing => (strings.learning, AppColors.warmInk),
      KnowledgeStatus.ready => (strings.learnedLabel, AppColors.success),
      KnowledgeStatus.failed => (strings.couldntRead, AppColors.hot),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconBubble(
                color: AppColors.surfaceMuted,
                size: 40,
                child: Icon(
                  AppIcons.knowledge(s.type),
                  size: 20,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      style: t.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (s.status == KnowledgeStatus.ready)
                          PopIn(
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: AppColors.success,
                            ),
                          ),
                        if (s.status == KnowledgeStatus.failed)
                          Icon(
                            Icons.error_outline_rounded,
                            size: 15,
                            color: AppColors.hot,
                          ),
                        if (s.status == KnowledgeStatus.ready ||
                            s.status == KnowledgeStatus.failed)
                          const SizedBox(width: 4),
                        Text(
                          label,
                          style: t.labelMedium?.copyWith(color: color),
                        ),
                        if (s.detail != null) ...[
                          Text(' · ', style: t.bodySmall),
                          Flexible(
                            child: Text(
                              s.detail!,
                              style: t.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: strings.remove,
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ),
          if (s.status == KnowledgeStatus.uploading ||
              s.status == KnowledgeStatus.processing) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 54, right: 10),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: s.progress),
                duration: AppMotion.of(context, AppMotion.base),
                builder: (_, v, _) => LinearProgressIndicator(
                  value: s.status == KnowledgeStatus.uploading ? v : null,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(9),
                  backgroundColor: AppColors.surfaceMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glyphs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../agent/owner_test_call_sheet.dart';

/// The three first things a new owner does, ticked from real data.
@immutable
class GettingStarted {
  const GettingStarted({
    required this.hasCustomers,
    required this.heardAi,
    required this.formShared,
  });

  /// ① At least one customer added (contacts, file or by hand).
  final bool hasCustomers;

  /// ② Heard the AI: a test call to their own phone, the in-app voice test,
  /// or any real call already made.
  final bool heardAi;

  /// ③ An enquiry form / lead source exists.
  final bool formShared;

  /// Builds the checklist from what the backend says. [leads] excludes the
  /// owner's own test number; [hasCalls] is any non-test call ever.
  factory GettingStarted.from({
    required int leads,
    required bool heardAi,
    required bool hasCalls,
    required int leadSources,
  }) => GettingStarted(
    hasCustomers: leads > 0,
    heardAi: heardAi || hasCalls,
    formShared: leadSources > 0,
  );

  int get done => [hasCustomers, heardAi, formShared].where((e) => e).length;
  static const total = 3;
  bool get allDone => done == total;
}

/// The checklist, or null while its data is still loading.
final gettingStartedProvider = Provider<GettingStarted?>((ref) {
  final dash = ref.watch(dashboardProvider).value;
  final sources = ref.watch(leadSourcesProvider);
  if (dash == null || sources.isLoading && !sources.hasValue) return null;
  return GettingStarted.from(
    leads: dash.leads,
    heardAi: ref.watch(heardAiProvider),
    hasCalls: ref.watch(weekResultsProvider).value?.hasCalls ?? false,
    leadSources: sources.value?.length ?? 0,
  );
});

/// The owner hid the "Getting started" card.
final checklistDismissedProvider = NotifierProvider<ChecklistDismissed, bool>(
  ChecklistDismissed.new,
);

class ChecklistDismissed extends Notifier<bool> {
  @override
  bool build() {
    try {
      return ref.watch(localPrefsProvider).checklistDismissed;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = true;
    await ref.read(localPrefsProvider).setChecklistDismissed(true);
  }
}

/// "Getting started" on Home: three big numbered one-tap steps. When the
/// last step is ticked while the card is on screen, it turns into a short
/// "You're all set" with the mascot celebrating; after that (or when the
/// owner hides it) it is gone.
class GettingStartedCard extends ConsumerStatefulWidget {
  const GettingStartedCard({super.key});

  @override
  ConsumerState<GettingStartedCard> createState() => _GettingStartedState();
}

/// Whether the owner saw the checklist unfinished in this app session, so
/// finishing it deserves a moment.
class ChecklistSession {
  ChecklistSession._();
  static bool sawIncomplete = false;
}

class _GettingStartedState extends ConsumerState<GettingStartedCard> {
  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gettingStartedProvider);
    final dismissed = ref.watch(checklistDismissedProvider);
    if (g != null && !g.allDone && !dismissed) {
      ChecklistSession.sawIncomplete = true;
    }
    final show =
        g != null &&
        !dismissed &&
        (!g.allDone || ChecklistSession.sawIncomplete);
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: SwapFade(
                child: g.allDone
                    ? const _AllSet(key: ValueKey('done'))
                    : _Card(key: const ValueKey('steps'), g: g),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

class _AllSet extends ConsumerWidget {
  const _AllSet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('getting-started-done'),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
      ),
      child: Row(
        children: [
          const Mascot(state: MascotState.celebrating, size: 72),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.gsAllSet, style: t.titleMedium),
                Text(s.gsAllSetBody, style: t.bodyMedium),
              ],
            ),
          ),
          TextButton(
            key: const Key('getting-started-hide'),
            onPressed: () =>
                ref.read(checklistDismissedProvider.notifier).dismiss(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.inkSoft,
              minimumSize: const Size(48, 48),
            ),
            child: Text(s.gsHide),
          ),
        ],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({super.key, required this.g});
  final GettingStarted g;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('getting-started'),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.sm,
        AppSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(s.gsTitle, style: t.titleLarge),
                    ),
                    Text(
                      s.gsProgress(g.done, GettingStarted.total),
                      style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('getting-started-hide'),
                onPressed: () =>
                    ref.read(checklistDismissedProvider.notifier).dismiss(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.inkSoft,
                  minimumSize: const Size(48, 48),
                ),
                child: Text(s.gsHide),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          // Segmented progress: one bar per step.
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: Row(
              children: [
                for (var i = 0; i < GettingStarted.total; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: AnimatedContainer(
                      duration: AppMotion.of(context, AppMotion.slow),
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < g.done
                            ? AppColors.success
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          _Step(
            n: 1,
            done: g.hasCustomers,
            title: s.gsContacts,
            glyph: AppGlyphs.customers,
            onTap: () => context.push('/leads/contacts'),
          ),
          _Step(
            n: 2,
            done: g.heardAi,
            title: s.gsHear,
            glyph: AppGlyphs.call,
            onTap: () => showOwnerTestCallSheet(context),
          ),
          _Step(
            n: 3,
            done: g.formShared,
            title: s.gsForm,
            subtitle: s.getCustomersAutoSub,
            glyph: AppGlyphs.qr,
            onTap: () => context.push('/leads/auto'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.done,
    required this.title,
    required this.glyph,
    required this.onTap,
    this.subtitle,
  });
  final int n;
  final bool done;
  final String title;
  final String? subtitle;
  final AppGlyphs glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: done ? '$n. $title, ${s.gsDone}' : '$n. $title',
      excludeSemantics: true,
      child: InkWell(
        key: Key('getting-started-$n'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              AppSpace.sm,
              AppSpace.sm,
              AppSpace.sm,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.base),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.successSoft : AppColors.brandSoft,
                  ),
                  child: done
                      ? Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                          size: 24,
                        )
                      : Text(
                          '$n',
                          style: t.titleLarge?.copyWith(
                            color: AppColors.brandDeep,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleMedium?.copyWith(
                          color: done ? AppColors.inkFaint : AppColors.ink,
                          fontWeight: done ? FontWeight.w500 : null,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.inkFaint,
                        ),
                      ),
                      if (subtitle != null && !done)
                        Text(
                          subtitle!,
                          style: t.bodyMedium?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!done) ...[
                  const SizedBox(width: AppSpace.sm),
                  AppGlyph(glyph, color: AppColors.brand),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

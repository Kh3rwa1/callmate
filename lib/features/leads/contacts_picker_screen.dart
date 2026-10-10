import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../services/contacts/contacts_source.dart';

enum _Stage { disclosure, loading, denied, ready, failed }

/// Pick customers straight from the phone's contacts: the way an owner
/// who has never seen a CSV file adds the people he already knows.
///
/// Big rows, a search box, tick the people, one button to add them.
class ContactsPickerScreen extends ConsumerStatefulWidget {
  const ContactsPickerScreen({super.key});

  @override
  ConsumerState<ContactsPickerScreen> createState() =>
      _ContactsPickerScreenState();
}

class _ContactsPickerScreenState extends ConsumerState<ContactsPickerScreen> {
  _Stage _stage = _Stage.loading;
  List<PhoneContact> _all = const [];
  final _picked = <String>{};
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Google Play: explain what we read and send BEFORE Android's prompt.
    if (_prefs?.contactsConsent ?? false) {
      _load();
    } else {
      _stage = _Stage.disclosure;
    }
  }

  LocalPrefs? get _prefs {
    try {
      return ref.read(localPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _agree() async {
    Haptics.tap();
    await _prefs?.setContactsConsent(true);
    await _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = ref.read(contactsSourceProvider);
    if (_stage != _Stage.loading) setState(() => _stage = _Stage.loading);
    try {
      if (!await source.requestAccess()) {
        if (mounted) setState(() => _stage = _Stage.denied);
        return;
      }
      final all = await source.load();
      if (!mounted) return;
      setState(() {
        _all = all;
        _stage = _Stage.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  List<PhoneContact> get _shown {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return [
      for (final c in _all)
        if (c.name.toLowerCase().contains(q) ||
            (digits.length >= 3 && c.phone.contains(digits)))
          c,
    ];
  }

  void _toggle(PhoneContact c) {
    Haptics.tap();
    setState(() {
      if (!_picked.remove(c.phone)) _picked.add(c.phone);
    });
  }

  Future<void> _add() async {
    final s = context.s;
    final chosen = [
      for (final c in _all)
        if (_picked.contains(c.phone)) c,
    ];
    if (chosen.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(leadRepoProvider).import([
        for (final c in chosen)
          NewLeadInput(
            name: c.name,
            phone: PhoneUtils.display(c.phone),
            source: 'Phone contacts',
          ),
      ]);
      ref.read(dataVersionProvider.notifier).bump();
      if (!mounted) return;
      setState(() => _busy = false);
      await _done(r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    }
  }

  Future<void> _done(LeadImportResult r) {
    final s = context.s;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
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
              children: [
                const SizedBox(height: 4),
                const Mascot(state: MascotState.celebrating, size: 120),
                const SizedBox(height: 8),
                Text(
                  s.nImported(r.imported),
                  style: t.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                if (r.skipped > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(s.nSkipped(r.skipped), style: t.bodyMedium),
                  ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: s.callThemNow,
                  icon: Icons.phone_forwarded_rounded,
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pushReplacement('/campaign/new');
                  },
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/leads');
                  },
                  child: Text(s.later),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(s.ctTitle)),
      body: SwapFade(
        child: KeyedSubtree(
          key: ValueKey(_stage),
          child: switch (_stage) {
            _Stage.disclosure => _disclosure(context),
            _Stage.loading => const Center(
              child: Mascot(state: MascotState.thinking, size: 140),
            ),
            _Stage.denied => _denied(context),
            _Stage.failed => ErrorState(onRetry: _load),
            _Stage.ready => _list(context),
          },
        ),
      ),
    );
  }

  Widget _disclosure(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    Widget point(int i, IconData icon, String text) => Reveal(
      index: i,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 21, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(text, style: t.bodyLarge),
              ),
            ),
          ],
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
              child: Column(
                children: [
                  const PopIn(
                    child: Mascot(state: MascotState.waving, size: 130),
                  ),
                  const SizedBox(height: 12),
                  Reveal(
                    index: 1,
                    child: Semantics(
                      header: true,
                      child: Text(
                        s.ctDiscTitle,
                        style: t.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  point(2, Icons.contacts_rounded, s.ctDiscRead),
                  point(3, Icons.check_circle_rounded, s.ctDiscSend),
                  point(4, Icons.lock_rounded, s.ctDiscKeep),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              4,
              AppSpace.page,
              12,
            ),
            child: Column(
              children: [
                PrimaryButton(label: s.ctDiscAgree, onPressed: _agree),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(s.ctDiscNo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _denied(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(state: MascotState.waving, size: 150),
            const SizedBox(height: 16),
            Text(s.ctAccessTitle, style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              s.ctAccessBody,
              style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: s.ctAllow, onPressed: _load),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => ref.read(contactsSourceProvider).openSettings(),
              child: Text(s.openSettings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    if (_all.isEmpty) {
      return EmptyState(title: s.ctNone, mascot: MascotState.thinking);
    }
    final shown = _shown;
    final allShownPicked =
        shown.isNotEmpty && shown.every((c) => _picked.contains(c.phone));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.page,
            4,
            AppSpace.page,
            0,
          ),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: t.titleMedium,
            decoration: InputDecoration(
              hintText: s.ctSearch,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: AnimatedCount(
                  value: _picked.length,
                  format: (n) => '$n / ${_all.length}',
                  style: t.labelLarge?.copyWith(color: AppColors.inkSoft),
                ),
              ),
              TextButton(
                onPressed: shown.isEmpty
                    ? null
                    : () => setState(() {
                        if (allShownPicked) {
                          _picked.removeAll(shown.map((c) => c.phone));
                        } else {
                          _picked.addAll(shown.map((c) => c.phone));
                        }
                      }),
                child: Text(allShownPicked ? s.ctClear : s.ctSelectAll),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(s.ctNoMatch, style: t.bodyLarge))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    0,
                    AppSpace.page,
                    16,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final c = shown[i];
                    return _ContactRow(
                      contact: c,
                      selected: _picked.contains(c.phone),
                      onTap: () => _toggle(c),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              12,
              AppSpace.page,
              12,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: PrimaryButton(
              label: s.ctAddN(_picked.length),
              icon: Icons.person_add_alt_1_rounded,
              loading: _busy,
              onPressed: _picked.isEmpty ? null : _add,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.onTap,
  });
  final PhoneContact contact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      checked: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          shadow: false,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          color: selected ? AppColors.brandSoft : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          child: Row(
            children: [
              LeadAvatar(name: contact.name, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      PhoneUtils.display(contact.phone),
                      style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 1.25,
                child: Checkbox(value: selected, onChanged: (_) => onTap()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

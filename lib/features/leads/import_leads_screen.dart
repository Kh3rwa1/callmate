import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv.dart';
import '../../core/utils/file_pick.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

class ImportLeadsScreen extends ConsumerStatefulWidget {
  const ImportLeadsScreen({super.key});
  @override
  ConsumerState<ImportLeadsScreen> createState() => _ImportLeadsScreenState();
}

class _ImportLeadsScreenState extends ConsumerState<ImportLeadsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _interest;
  bool _busy = false;
  CsvLeadParseResult? _preview;
  String? _fileName;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// CSV parser messages are English; show them in the UI language.
  String _csvError(S s, String e) {
    if (e == 'The file is empty.') return s.csvEmpty;
    final m = RegExp(r'^Row (\d+): invalid phone number$').firstMatch(e);
    return m == null ? e : s.csvRowInvalid(m.group(1)!);
  }

  Future<void> _addOne() async {
    final s = context.s;
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(leadRepoProvider)
          .create(
            NewLeadInput(
              name: _name.text.trim(),
              phone: _phone.text,
              interest: _interest,
            ),
          );
      _name.clear();
      _phone.clear();
      Haptics.success();
      if (!mounted) return;
      setState(() => _interest = null);
      _snack(s.leadAdded);
    } catch (e) {
      if (mounted) _snack(friendlyError(e, s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCsv() async {
    final s = context.s;
    try {
      final f = await pickSingleFile(
        extensions: ['csv', 'txt'],
        maxBytes: 2 * 1024 * 1024,
      );
      if (f == null) return;
      final text = utf8.decode(f.bytes, allowMalformed: true);
      setState(() {
        _preview = CsvLeadParser.toLeads(text);
        _fileName = f.name;
      });
    } on FileTooLargeException {
      _snack(s.csvTooLarge);
    } catch (_) {
      _snack(s.csvUnreadable);
    }
  }

  void _useSample() {
    const sample =
        'Name,Phone,Interest,Source\n'
        'Riddhi Sen,98301 22334,Pricing,Facebook Ad\n'
        'Karan Mehta,+91 97480 11223,Demo request,Website form\n'
        'Moumita Paul,09007766554,Service enquiry,Referral\n'
        'Faizan Ali,8013344556,Pricing,Instagram\n'
        'Broken Row,12345,Pricing,Website form\n'
        'Tania Roy,7003322110,Product enquiry,Google Ads\n';
    Haptics.tap();
    setState(() {
      _preview = CsvLeadParser.toLeads(sample);
      _fileName = 'sample_leads.csv';
    });
  }

  Future<void> _import() async {
    final s = context.s;
    final p = _preview;
    if (p == null || p.leads.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(leadRepoProvider).import(p.leads);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _busy = false;
      });
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (ctx) {
          final t = Theme.of(ctx).textTheme;
          final skipped = r.skipped + p.skipped;
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
                  SuccessCheck(size: 76, color: AppColors.success),
                  const SizedBox(height: 16),
                  Reveal(
                    index: 3,
                    child: Text(
                      s.nImported(r.imported),
                      style: t.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (skipped > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(s.nSkipped(skipped), style: t.bodyMedium),
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
                      context.pop();
                    },
                    child: Text(s.later),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(friendlyError(e, s));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final p = _preview;
    final wf = ref.watch(workflowProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.addLeadsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 32),
        children: [
          // The easy way first: the people already in his phone.
          Reveal(
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBubble(
                        size: 48,
                        child: Icon(
                          Icons.contacts_rounded,
                          color: AppColors.brand,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.ctFromContacts, style: t.titleMedium),
                            Text(s.ctFromContactsSub, style: t.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: s.ctChoose,
                    icon: Icons.contacts_outlined,
                    onPressed: _busy
                        ? null
                        : () => context.push('/leads/contacts'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Speed-to-lead: new enquiries arrive (and get called) by themselves.
          Reveal(
            child: AppCard(
              key: const Key('import-get-leads-automatically'),
              onTap: () => context.push('/leads/auto'),
              child: Row(
                children: [
                  IconBubble(
                    size: 48,
                    child: Icon(
                      Icons.bolt_rounded,
                      color: AppColors.brand,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.getLeadsAutomatically, style: t.titleMedium),
                        Text(s.leadCaptureEntrySubtitle, style: t.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
                ],
              ),
            ),
          ),
          Reveal(index: 1, child: SectionLabel(s.ctHaveFile)),
          Reveal(
            index: 1,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBubble(
                        size: 44,
                        color: AppColors.surfaceMuted,
                        child: Icon(
                          Icons.upload_file_outlined,
                          color: AppColors.ink,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.importCsv, style: t.titleMedium),
                            Text(s.csvColumns, style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwapFade(
                    child: p == null
                        ? SecondaryButton(
                            key: const ValueKey('choose'),
                            label: s.chooseFile,
                            icon: Icons.attach_file_rounded,
                            onPressed: _busy ? null : _pickCsv,
                          )
                        : SecondaryButton(
                            key: const ValueKey('another'),
                            label: s.chooseAnotherFile,
                            onPressed: _busy ? null : _pickCsv,
                          ),
                  ),
                  // Sample rows are real-format numbers: against a live
                  // backend they could be dialled, so offer them only in
                  // mock mode.
                  if (ref.watch(useMockProvider)) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: _useSample,
                        child: Text(s.trySample),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.slow),
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: p == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionLabel(
                        s.preview,
                        trailing: _fileName == null
                            ? null
                            : Flexible(
                                child: Text(
                                  _fileName!,
                                  style: t.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                      _Preview(
                        preview: p,
                        busy: _busy,
                        csvError: (e) => _csvError(s, e),
                        onImport: p.leads.isEmpty ? null : _import,
                      ),
                    ],
                  ),
          ),
          Reveal(index: 1, child: SectionLabel(s.orAddOne)),
          Reveal(
            index: 2,
            child: AppCard(
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: s.customerNameHint,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().length < 2 ? s.enterName : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: s.mobileNumberHint,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: (v) =>
                          PhoneUtils.isValid(v) ? null : s.validPhone,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('interest-$_interest'),
                      initialValue: _interest,
                      decoration: InputDecoration(
                        hintText: s.optionalField(s.data(wf.interestLabel)),
                        prefixIcon: const Icon(Icons.local_offer_outlined),
                      ),
                      dropdownColor: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.cardSm),
                      items: [
                        for (final c in wf.interestOptions)
                          DropdownMenuItem(value: c, child: Text(s.data(c))),
                      ],
                      onChanged: (v) => setState(() => _interest = v),
                    ),
                    const SizedBox(height: 16),
                    SecondaryButton(
                      label: s.addLead,
                      icon: Icons.add_rounded,
                      onPressed: _busy ? null : _addOne,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.preview,
    required this.busy,
    required this.csvError,
    required this.onImport,
  });
  final CsvLeadParseResult preview;
  final bool busy;
  final String Function(String) csvError;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final p = preview;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PopIn(
                child: Pill(
                  label: s.nReady(p.leads.length),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              if (p.skipped > 0)
                PopIn(
                  delay: const Duration(milliseconds: 80),
                  child: Pill(label: s.nSkipped(p.skipped)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, l) in p.leads.take(5).indexed)
            Reveal(
              index: i,
              offset: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.name,
                        style: t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      PhoneUtils.display(l.phone),
                      style: t.bodySmall,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ],
                ),
              ),
            ),
          if (p.leads.length > 5)
            Text(s.nMore(p.leads.length - 5), style: t.bodySmall),
          for (final e in p.errors)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: AppColors.hot,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      csvError(e),
                      style: t.bodySmall?.copyWith(color: AppColors.hot),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: s.importN(p.leads.length),
            loading: busy,
            onPressed: onImport,
          ),
        ],
      ),
    );
  }
}

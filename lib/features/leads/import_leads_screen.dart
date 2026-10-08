import 'dart:convert';

import '../../core/utils/file_pick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

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

  Future<void> _addOne() async {
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
      _snack(
        'Lead added ✓ Your AI employee will call them in the next campaign.',
      );
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCsv() async {
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
      _snack('That file is over 2 MB. Split it and try again.');
    } catch (_) {
      _snack('Couldn\'t read that file. Make sure it\'s a CSV.');
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
    setState(() {
      _preview = CsvLeadParser.toLeads(sample);
      _fileName = 'sample_leads.csv';
    });
  }

  Future<void> _import() async {
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
                  const Mascot(state: MascotState.success, size: 120),
                  const SizedBox(height: 10),
                  Text('${r.imported} leads imported', style: t.headlineSmall),
                  if (r.skipped + p.skipped > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${r.skipped + p.skipped} skipped (duplicates or invalid numbers)',
                        style: t.bodyMedium,
                      ),
                    ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Call them now',
                    icon: Icons.phone_forwarded_rounded,
                    color: AppColors.brand,
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
                    child: const Text('Later'),
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
        _snack(friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Add leads')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBubble(
                      color: AppColors.brandSoft,
                      child: Emoji('📥'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Import from CSV', style: t.titleMedium),
                          Text(
                            'Columns: Name, Phone, Interest (optional), Source',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Choose CSV file',
                  icon: Icons.upload_file_rounded,
                  onPressed: _busy ? null : _pickCsv,
                ),
                // Sample rows are real-format numbers: against a live backend
                // they could be dialled, so offer them only in mock mode.
                if (ref.watch(useMockProvider)) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: _useSample,
                      child: const Text('Try with sample leads'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (p != null) ...[
            SectionLabel('Preview · ${_fileName ?? ''}'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Pill(
                        label: '${p.leads.length} ready',
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      if (p.skipped > 0)
                        Pill(
                          label: '${p.skipped} skipped',
                          color: AppColors.hot,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final l in p.leads.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(l.name, style: t.titleSmall)),
                          Text(PhoneUtils.display(l.phone), style: t.bodySmall),
                        ],
                      ),
                    ),
                  if (p.leads.length > 5)
                    Text('+ ${p.leads.length - 5} more', style: t.bodySmall),
                  for (final e in p.errors)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '⚠️ $e',
                        style: t.bodySmall?.copyWith(color: AppColors.hot),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Import ${p.leads.length} leads',
                    loading: _busy,
                    color: AppColors.success,
                    onPressed: p.leads.isEmpty ? null : _import,
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('Or add one lead'),
          AppCard(
            child: Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Customer name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                      prefixText: '',
                    ),
                    validator: (v) => PhoneUtils.isValid(v)
                        ? null
                        : 'Enter a valid 10-digit mobile number',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _interest,
                    decoration: InputDecoration(
                      hintText:
                          '${ref.watch(workflowProvider).interestLabel} (optional)',
                      prefixIcon: const Icon(Icons.local_offer_outlined),
                    ),
                    items: [
                      for (final c
                          in ref.watch(workflowProvider).interestOptions)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _interest = v),
                  ),
                  const SizedBox(height: 16),
                  SecondaryButton(
                    label: 'Add lead',
                    icon: Icons.add_rounded,
                    onPressed: _busy ? null : _addOne,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

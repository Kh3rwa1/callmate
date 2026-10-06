import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

/// Human-friendly agent settings. No prompts, no model knobs.
class EditAgentScreen extends ConsumerStatefulWidget {
  const EditAgentScreen({super.key});
  @override
  ConsumerState<EditAgentScreen> createState() => _EditAgentScreenState();
}

class _EditAgentScreenState extends ConsumerState<EditAgentScreen> {
  Agent? _a;
  final _name = TextEditingController();
  final _transfer = TextEditingController();
  bool _saving = false;
  static const _allLanguages = [
    'Bengali',
    'Hindi',
    'English',
    'Odia',
    'Tamil',
    'Telugu',
    'Marathi',
    'Gujarati',
    'Kannada',
    'Malayalam',
    'Punjabi',
  ];

  @override
  void dispose() {
    _name.dispose();
    _transfer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = _a!;
    if (_name.text.trim().isEmpty) return;
    if (_transfer.text.trim().isNotEmpty && !PhoneUtils.isValid(_transfer.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the transfer number')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(businessRepoProvider).saveAgent(a.copyWith(name: _name.text.trim(), transferNumber: _transfer.text.trim()));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_name.text.trim()} updated ✓')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(agentProvider);
    if (_a == null && async.value != null) {
      _a = async.value;
      _name.text = _a!.name;
      _transfer.text = _a!.transferNumber ?? '';
    }
    final a = _a;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit AI Employee')),
      body: a == null
          ? const SkeletonList(count: 3)
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 120),
              children: [
                const Center(child: Mascot(size: 120)),
                const SectionLabel('Identity'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Name', style: t.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(hintText: 'Riya'),
                      ),
                      const SizedBox(height: 16),
                      Text('Role', style: t.titleSmall),
                      const SizedBox(height: 8),
                      Text(a.role, style: t.bodyLarge),
                    ],
                  ),
                ),
                const SectionLabel('Languages'),
                AppCard(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in _allLanguages)
                        FilterChip(
                          label: Text(l),
                          selected: a.languages.contains(l),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: a.languages.contains(l) ? Colors.white : AppColors.inkSoft,
                          ),
                          onSelected: (on) {
                            final next = on ? [...a.languages, l] : a.languages.where((x) => x != l).toList();
                            if (next.isEmpty) return;
                            setState(() => _a = a.copyWith(languages: next));
                          },
                        ),
                    ],
                  ),
                ),
                const SectionLabel('Personality'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.personalityLabel, style: t.titleMedium),
                      Slider(
                        value: a.formality,
                        divisions: 10,
                        semanticFormatterCallback: (v) => v < 0.5 ? 'More friendly' : 'More formal',
                        onChanged: (v) => setState(() => _a = a.copyWith(formality: v)),
                      ),
                      Row(
                        children: [
                          Text('😊 Friendly', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text('Formal 👔', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Calling hours'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${Fmt.hour(a.callingHoursStart)} – ${Fmt.hour(a.callingHoursEnd)}', style: t.titleMedium),
                      RangeSlider(
                        values: RangeValues(a.callingHoursStart.toDouble(), a.callingHoursEnd.toDouble()),
                        min: 8,
                        max: 21,
                        divisions: 13,
                        onChanged: (v) {
                          if (v.end - v.start < 2) return;
                          setState(() => _a = a.copyWith(callingHoursStart: v.start.round(), callingHoursEnd: v.end.round()));
                        },
                      ),
                      Text('Riya never calls outside these hours.', style: t.bodySmall),
                    ],
                  ),
                ),
                const SectionLabel('Hot lead transfer'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('When a lead wants to talk now, Riya can transfer the call to:', style: t.bodyMedium),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _transfer,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: 'Counsellor number', prefixIcon: Icon(Icons.support_agent_rounded)),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Status'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SwitchListTile(
                    value: a.status == AgentStatus.active,
                    title: Text(a.status == AgentStatus.active ? '${a.name} is active' : '${a.name} is paused', style: t.titleSmall),
                    subtitle: const Text('Pause to stop all calling immediately'),
                    onChanged: (v) => setState(() => _a = a.copyWith(status: v ? AgentStatus.active : AgentStatus.paused)),
                  ),
                ),
                const SizedBox(height: 14),
                AppCard(
                  onTap: () => context.push('/agent/teach'),
                  child: Row(
                    children: [
                      const Emoji('📚'),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Teach Your AI', style: t.titleSmall)),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: a == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 8, AppSpace.page, 12),
                child: PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _save),
              ),
            ),
    );
  }
}

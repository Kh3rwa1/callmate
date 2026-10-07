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
import '../../data/templates/templates.dart';

/// Human-friendly agent settings. No prompts, no model knobs.
class EditAgentScreen extends ConsumerStatefulWidget {
  const EditAgentScreen({super.key});
  @override
  ConsumerState<EditAgentScreen> createState() => _EditAgentScreenState();
}

class _EditAgentScreenState extends ConsumerState<EditAgentScreen> {
  Agent? _a;
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _goal = TextEditingController();
  final _transfer = TextEditingController();
  static const _voices = [
    'Warm · Female',
    'Calm · Female',
    'Friendly · Male',
    'Confident · Male',
  ];
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
    _role.dispose();
    _goal.dispose();
    _transfer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = _a!;
    if (_name.text.trim().isEmpty) return;
    if (_transfer.text.trim().isNotEmpty &&
        !PhoneUtils.isValid(_transfer.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the transfer number')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(businessRepoProvider)
          .saveAgent(
            a.copyWith(
              name: _name.text.trim(),
              role: _role.text.trim().isEmpty ? a.role : _role.text.trim(),
              roleKind: EmployeeRoleKind.fromRole(
                _role.text.trim().isEmpty ? a.role : _role.text.trim(),
              ).name,
              goal: _goal.text.trim().isEmpty ? a.goal : _goal.text.trim(),
              transferNumber: _transfer.text.trim(),
            ),
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_name.text.trim()} updated ✓')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final async = ref.watch(agentProvider);
    if (_a == null && async.value != null) {
      _a = async.value;
      _name.text = _a!.name;
      _role.text = _a!.role;
      _goal.text = _a!.goal;
      _transfer.text = _a!.transferNumber ?? '';
    }
    final a = _a;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit AI Employee')),
      body: a == null
          ? const SkeletonList(count: 3)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                0,
                AppSpace.page,
                120,
              ),
              children: [
                Center(
                  child: Mascot(
                    size: 120,
                    role: EmployeeRoleKind.fromRole(_role.text),
                  ),
                ),
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
                        decoration: const InputDecoration(
                          hintText: 'e.g. Maya, Riya, Arjun',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Role', style: t.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _role,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. Sales Assistant, Appointment Assistant',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Goal', style: t.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _goal,
                        maxLines: 2,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. Convert enquiries into qualified opportunities',
                        ),
                      ),
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
                            color: a.languages.contains(l)
                                ? Colors.white
                                : AppColors.inkSoft,
                          ),
                          onSelected: (on) {
                            final next = on
                                ? [...a.languages, l]
                                : a.languages.where((x) => x != l).toList();
                            if (next.isEmpty) return;
                            setState(() => _a = a.copyWith(languages: next));
                          },
                        ),
                    ],
                  ),
                ),
                const SectionLabel('Voice'),
                AppCard(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in _voices)
                        ChoiceChip(
                          label: Text(v),
                          selected: a.voice == v,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: a.voice == v
                                ? Colors.white
                                : AppColors.inkSoft,
                          ),
                          onSelected: (_) =>
                              setState(() => _a = a.copyWith(voice: v)),
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
                        semanticFormatterCallback: (v) =>
                            v < 0.5 ? 'More friendly' : 'More formal',
                        onChanged: (v) =>
                            setState(() => _a = a.copyWith(formality: v)),
                      ),
                      Row(
                        children: [
                          Text(
                            '😊 Friendly',
                            style: t.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Formal 👔',
                            style: t.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                      Text(
                        '${Fmt.hour(a.callingHoursStart)} – ${Fmt.hour(a.callingHoursEnd)}',
                        style: t.titleMedium,
                      ),
                      RangeSlider(
                        values: RangeValues(
                          a.callingHoursStart.toDouble(),
                          a.callingHoursEnd.toDouble(),
                        ),
                        min: 8,
                        max: 21,
                        divisions: 13,
                        onChanged: (v) {
                          if (v.end - v.start < 2) return;
                          setState(
                            () => _a = a.copyWith(
                              callingHoursStart: v.start.round(),
                              callingHoursEnd: v.end.round(),
                            ),
                          );
                        },
                      ),
                      Text(
                        '${a.name} never calls outside these hours.',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Hot lead transfer'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'When a lead wants to talk now, ${a.name} can transfer the call to:',
                        style: t.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _transfer,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText:
                              '${ref.watch(workflowProvider).humanLabel} number',
                          prefixIcon: const Icon(Icons.support_agent_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Status'),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: SwitchListTile(
                    value: a.status == AgentStatus.active,
                    title: Text(
                      a.status == AgentStatus.active
                          ? '${a.name} is active'
                          : '${a.name} is paused',
                      style: t.titleSmall,
                    ),
                    subtitle: const Text(
                      'Pause to stop all calling immediately',
                    ),
                    onChanged: (v) => setState(
                      () => _a = a.copyWith(
                        status: v ? AgentStatus.active : AgentStatus.paused,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AppCard(
                  onTap: () => context.push('/agent/teach'),
                  child: Row(
                    children: [
                      const Emoji('📚'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Business Knowledge · Teach Your AI',
                          style: t.titleSmall,
                        ),
                      ),
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  8,
                  AppSpace.page,
                  12,
                ),
                child: PrimaryButton(
                  label: 'Save changes',
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
            ),
    );
  }
}

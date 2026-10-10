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
                    size: 96,
                    role: EmployeeRoleKind.fromRole(_role.text),
                  ),
                ),
                const SectionLabel('Identity'),
                AppCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _role,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Role'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _goal,
                        maxLines: 2,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Goal'),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('Voice & language'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('Languages'),
                      Wrap(
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
                                setState(
                                  () => _a = a.copyWith(languages: next),
                                );
                              },
                            ),
                        ],
                      ),
                      const _GroupDivider(),
                      const _FieldLabel('Voice'),
                      Wrap(
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
                    ],
                  ),
                ),
                const SectionLabel('Behaviour'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Personality', value: a.personalityLabel),
                      Slider(
                        value: a.formality,
                        divisions: 10,
                        semanticFormatterCallback: (v) =>
                            v < 0.5 ? 'More friendly' : 'More formal',
                        onChanged: (v) =>
                            setState(() => _a = a.copyWith(formality: v)),
                      ),
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            Text('Friendly', style: t.bodySmall),
                            const Spacer(),
                            Text('Formal', style: t.bodySmall),
                          ],
                        ),
                      ),
                      const _GroupDivider(),
                      _FieldLabel(
                        'Calling hours',
                        value:
                            '${Fmt.hour(a.callingHoursStart)} – ${Fmt.hour(a.callingHoursEnd)}',
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
                    ],
                  ),
                ),
                const SectionLabel('Calls'),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TextField(
                          controller: _transfer,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Transfer hot leads to',
                            hintText:
                                '${ref.watch(workflowProvider).humanLabel} number',
                            prefixIcon: const Icon(Icons.support_agent_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.only(right: 4),
                        value: a.status == AgentStatus.active,
                        title: Text(
                          a.status == AgentStatus.active
                              ? '${a.name} is active'
                              : '${a.name} is paused',
                          style: t.titleSmall,
                        ),
                        onChanged: (v) => setState(
                          () => _a = a.copyWith(
                            status: v ? AgentStatus.active : AgentStatus.paused,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  onTap: () => context.push('/agent/teach'),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Teach Your AI', style: t.titleSmall),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.inkFaint,
                      ),
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

/// Small label above a control, with an optional value on the right.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.value});
  final String text;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(text, style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
          if (value != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value!,
                style: t.titleSmall,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Divider(height: 1, thickness: 1, color: AppColors.border),
  );
}

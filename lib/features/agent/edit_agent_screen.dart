import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/calling_hours.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_persona.dart';

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
  bool _saving = false;
  String? _nameError;
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
    final s = context.s;
    final a = _a!;
    if (_name.text.trim().isEmpty) {
      Haptics.warn();
      setState(() => _nameError = s.nameRequired);
      return;
    }
    if (_transfer.text.trim().isNotEmpty &&
        !PhoneUtils.isValid(_transfer.text)) {
      Haptics.warn();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.checkTransferNumber)));
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
      Haptics.success();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.nameUpdated(_name.text.trim()))));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final async = ref.watch(agentProvider);
    if (_a == null && async.value != null) {
      final loaded = async.value!;
      // Older accounts may hold hours outside the TRAI window; saving them
      // as-is would be rejected, so start from the clamped window.
      final hours = traiCallingHours(
        loaded.callingHoursStart,
        loaded.callingHoursEnd,
      );
      _a = loaded.copyWith(
        callingHoursStart: hours.start.round(),
        callingHoursEnd: hours.end.round(),
      );
      _name.text = _a!.name;
      _role.text = _a!.role;
      _goal.text = _a!.goal;
      _transfer.text = _a!.transferNumber ?? '';
    }
    final a = _a;
    return Scaffold(
      appBar: AppBar(title: Text(s.editAiEmployee)),
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
                  child: PopIn(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_name, _role]),
                      builder: (_, _) => EmployeeAvatar(
                        name: _name.text,
                        role: EmployeeRoleKind.fromRole(_role.text),
                        size: 88,
                      ),
                    ),
                  ),
                ),
                SectionLabel(s.identity),
                AppCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: s.nameLabel,
                          errorText: _nameError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _role,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: s.roleLabel),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _goal,
                        maxLines: 2,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(labelText: s.goal),
                      ),
                    ],
                  ),
                ),
                SectionLabel(s.voiceAndLanguage),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(s.languagesLabel),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in _allLanguages)
                            FilterChip(
                              label: Text(s.data(l)),
                              selected: a.languages.contains(l),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: a.languages.contains(l)
                                    ? AppColors.onInverse
                                    : AppColors.inkSoft,
                              ),
                              onSelected: (on) {
                                Haptics.tap();
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
                      _FieldLabel(s.voice),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Only what you can actually hear: a woman's or a
                          // man's voice. "Warm" vs "Calm" sounded the same.
                          for (final (male, label) in [
                            (false, s.obVoiceFemale),
                            (true, s.obVoiceMale),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: isMaleVoice(a.voice) == male,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isMaleVoice(a.voice) == male
                                    ? AppColors.onInverse
                                    : AppColors.inkSoft,
                              ),
                              onSelected: (_) {
                                Haptics.tap();
                                setState(
                                  () => _a = a.copyWith(
                                    voice: male ? maleVoice : femaleVoice,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionLabel(s.behaviour),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(
                        s.personality,
                        value: s.data(a.personalityLabel),
                      ),
                      Slider(
                        value: a.formality,
                        divisions: 10,
                        semanticFormatterCallback: (v) =>
                            v < 0.5 ? s.moreFriendly : s.moreFormal,
                        onChanged: (v) =>
                            setState(() => _a = a.copyWith(formality: v)),
                      ),
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            Text(s.friendly, style: t.bodySmall),
                            const Spacer(),
                            Text(s.formal, style: t.bodySmall),
                          ],
                        ),
                      ),
                      const _GroupDivider(),
                      _FieldLabel(
                        s.callingHours,
                        value:
                            '${Fmt.hour(a.callingHoursStart)} – ${Fmt.hour(a.callingHoursEnd)}',
                      ),
                      RangeSlider(
                        values: traiCallingHours(
                          a.callingHoursStart,
                          a.callingHoursEnd,
                        ),
                        min: kTraiEarliestHour.toDouble(),
                        max: kTraiLatestHour.toDouble(),
                        divisions: kTraiLatestHour - kTraiEarliestHour,
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
                SectionLabel(s.callsSection),
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
                            labelText: s.transferHotLeadsTo,
                            hintText: s.humanNumberHint(
                              s.data(ref.watch(workflowProvider).humanLabel),
                            ),
                            prefixIcon: const Icon(Icons.support_agent_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.only(right: 4),
                        value: a.status == AgentStatus.active,
                        title: SwapFade(
                          child: Text(
                            a.status == AgentStatus.active
                                ? s.isActiveNamed(a.name)
                                : s.isPausedNamed(a.name),
                            key: ValueKey(a.status),
                            style: t.titleSmall,
                          ),
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
                      Expanded(child: Text(s.teachYourAi, style: t.titleSmall)),
                      Icon(
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
                  label: s.saveChanges,
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
    child: Divider(height: 1, thickness: 1),
  );
}

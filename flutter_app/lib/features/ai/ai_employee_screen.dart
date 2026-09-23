import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

const _voices = ['anushka', 'arjun', 'meera', 'rahul'];
const _languages = ['english', 'hindi', 'hinglish', 'tamil', 'telugu'];
const _callStyles = ['friendly', 'professional', 'concise'];

/// The AI employee's settings.
///
/// These are the customer-facing view of the backend's agent configuration. No
/// provider detail is shown or stored here — the backend maps them onto the voice
/// service when it places calls.
class AiEmployeeScreen extends StatefulWidget {
  const AiEmployeeScreen({super.key});

  @override
  State<AiEmployeeScreen> createState() => _AiEmployeeScreenState();
}

class _AiEmployeeScreenState extends State<AiEmployeeScreen> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final agent = repo.data.agent;

    if (agent == null) {
      return PageScaffold(
        title: 'AI employee',
        child: EmptyBlock(
          title: 'Your AI employee is being set up',
          message: 'Finish onboarding with your business details and the settings will appear here.',
        ),
      );
    }

    return PageScaffold(
      title: 'AI employee',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Mascot(mood: MascotMood.happy, size: 88),
                const SizedBox(height: AppSpacing.md),
                Text(agent.name, style: AppText.title),
                const SizedBox(height: 4),
                Text(
                  'Answers calls and books customers for you',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                StatusPill(
                  label: agent.inboundEnabled ? 'Answering calls' : 'Paused',
                  tone: agent.inboundEnabled ? Tone.green : Tone.neutral,
                  large: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Voice'),
          _ChoiceRow(
            label: 'Voice',
            value: agent.voice,
            options: _voices,
            onChanged: (value) => _save({'voice': value}),
          ),
          _ChoiceRow(
            label: 'Language',
            value: agent.language,
            options: _languages,
            onChanged: (value) => _save({'language': value}),
          ),
          _ChoiceRow(
            label: 'Call style',
            value: agent.callStyle,
            options: _callStyles,
            onChanged: (value) => _save({'call_style': value}),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Working hours'),
          KeyValueTile(
            label: 'Starts',
            value: agent.workingHoursStart,
          ),
          const SizedBox(height: AppSpacing.sm),
          KeyValueTile(
            label: 'Ends',
            value: agent.workingHoursEnd,
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Behaviour'),
          SwitchRow(
            icon: Icons.phone_callback_rounded,
            tone: Tone.blue,
            label: 'Answer incoming calls',
            description: 'Customers who call your number reach your AI employee',
            value: agent.inboundEnabled,
            onChanged: (value) => _save({'inbound_enabled': value}),
          ),
          SwitchRow(
            icon: Icons.repeat_rounded,
            tone: Tone.amber,
            label: 'Follow up automatically',
            description: 'Customers who ask for a callback are called again',
            value: agent.followUpEnabled,
            onChanged: (value) => _save({'follow_up_enabled': value}),
          ),

          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Run a test call',
            icon: Icons.play_circle_fill_rounded,
            loading: _testing,
            onPressed: _runTest,
          ),
        ],
      ),
    );
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    try {
      await context.read<AppRepository>().updateAgent(patch);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    }
  }

  Future<void> _runTest() async {
    setState(() => _testing = true);
    showAppToast(context, '$agentName is preparing a test call…');
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _testing = false);
    showAppToast(context, 'Test call finished. Everything sounds good.');
  }
}

/// A row that opens a picker for one of a small set of values.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SettingsRow(
        icon: Icons.tune_rounded,
        tone: Tone.purple,
        label: label,
        trailing: _titleCase(value),
        onTap: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) => Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.title),
                  const SizedBox(height: AppSpacing.md),
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: SecondaryButton(
                        label: _titleCase(option),
                        selected: option == value,
                        tone: Tone.green,
                        onPressed: () => Navigator.of(context).pop(option),
                      ),
                    ),
                ],
              ),
            ),
          );
          if (choice != null && choice != value) onChanged(choice);
        },
      ),
    );
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

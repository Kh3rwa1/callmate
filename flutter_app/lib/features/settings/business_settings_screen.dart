import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

/// The business's own details, plus how the AI employee introduces it.
///
/// The name and number are tenant configuration owned by the backend, so they are
/// shown rather than edited here. What the owner *can* change is how their AI
/// employee greets people, which the backend supports directly.
class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _greeting = TextEditingController();
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _greeting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppRepository>().data;

    if (!_prefilled) {
      _prefilled = true;
      _greeting.text = data.agent?.greeting ?? '';
    }

    return PageScaffold(
      title: 'Business details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Your business'),
          KeyValueTile(label: 'Business name', value: data.organisation.name),
          KeyValueTile(
            label: 'Phone number',
            value: data.phoneNumber?.number ?? 'Not set',
          ),
          KeyValueTile(
            label: 'Voice mode',
            value: data.organisation.voiceMode == 'mock' ? 'Practice mode' : 'Live',
            tone: data.organisation.voiceMode == 'mock' ? Tone.amber : Tone.green,
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'How your AI employee sounds'),
          SurfaceCard(
            child: Row(
              children: [
                const Mascot(mood: MascotMood.happy, size: 54),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.agent?.name ?? agentName,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${data.agent?.language ?? 'english'} · '
                        '${data.agent?.callStyle ?? 'friendly'}',
                        style: AppText.caption.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Greeting'),
          LabeledField(
            controller: _greeting,
            label: 'What $agentName says when answering',
            lines: 3,
          ),

          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save greeting',
            loading: _saving,
            onPressed: _save,
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(
            data.organisation.voiceMode == 'mock'
                ? 'You are in practice mode: calls are simulated so you can try '
                    'everything before going live.'
                : 'You are live: calls are placed by our backend on your behalf.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppRepository>().updateAgent({'greeting': _greeting.text.trim()});
      if (mounted) showAppToast(context, 'Greeting saved');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

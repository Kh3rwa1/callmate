import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';

/// Confirms and starts an AI call to [l], handling permissions and errors.
Future<void> handleLeadCall(
  BuildContext context,
  WidgetRef ref,
  Lead l,
  String agentName,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Call ${l.name}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              PhoneUtils.display(l.phone),
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.brandSoft,
                child: Icon(Icons.smart_toy_rounded, color: AppColors.brand),
              ),
              title: Text('AI Call with $agentName (Sarvam AI)'),
              subtitle: const Text(
                'Agent calls lead phone directly with voice AI',
              ),
              onTap: () => Navigator.pop(ctx, 'ai_call'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.infoSoft,
                child: Icon(Icons.mic_rounded, color: AppColors.info),
              ),
              title: Text('Talk in-app with $agentName'),
              subtitle: const Text('Live conversational voice session in-app'),
              onTap: () => Navigator.pop(ctx, 'in_app'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.surfaceMuted,
                child: Icon(Icons.call_rounded, color: AppColors.inkSoft),
              ),
              title: const Text('Manual Phone Call'),
              subtitle: const Text('Open phone dialer using your SIM card'),
              onTap: () => Navigator.pop(ctx, 'sim_call'),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  if (action == 'ai_call') {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calling ${l.name} via Sarvam AI voice agent... 📞'),
        ),
      );
      await ref.read(callRepoProvider).triggerCall(l.id);
      ref.invalidate(leadCallsProvider(l.id));
      ref.read(dataVersionProvider.notifier).bump();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$agentName is calling ${l.name}! Call logged in activity.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  } else if (action == 'in_app') {
    context.push('/voice-test');
  } else if (action == 'sim_call') {
    final d = PhoneUtils.normalize(l.phone);
    if (d != null) launchUrl(Uri.parse('tel:+$d'));
  }
}

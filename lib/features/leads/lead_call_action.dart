import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
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
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Call ${l.name}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                PhoneUtils.display(l.phone),
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const IconBubble(
                size: 40,
                color: AppColors.brandSoft,
                child: Icon(Icons.graphic_eq_rounded, color: AppColors.brand),
              ),
              title: Text('AI Call with $agentName (Sarvam AI)'),
              subtitle: const Text('Calls their phone'),
              onTap: () => Navigator.pop(ctx, 'ai_call'),
            ),
            ListTile(
              leading: const IconBubble(
                size: 40,
                color: AppColors.surfaceMuted,
                child: Icon(Icons.mic_none_rounded, color: AppColors.ink),
              ),
              title: Text('Talk in-app with $agentName'),
              subtitle: const Text('Voice test in the app'),
              onTap: () => Navigator.pop(ctx, 'in_app'),
            ),
            ListTile(
              leading: const IconBubble(
                size: 40,
                color: AppColors.surfaceMuted,
                child: Icon(Icons.call_outlined, color: AppColors.ink),
              ),
              title: const Text('Call from my phone'),
              subtitle: const Text('Uses your SIM'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Calling ${l.name}…')));
      await ref.read(callRepoProvider).triggerCall(l.id);
      ref.invalidate(leadCallsProvider(l.id));
      ref.read(dataVersionProvider.notifier).bump();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$agentName is calling ${l.name}')),
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

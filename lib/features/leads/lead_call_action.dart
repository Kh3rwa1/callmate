import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Confirms and starts a call to [l]: an AI call, an in-app voice test, or
/// a normal call from the owner's phone. True when an AI call was placed.
Future<bool> handleLeadCall(
  BuildContext context,
  WidgetRef ref,
  Lead l,
  String agentName,
) async {
  final s = context.s;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      Widget option(
        String value,
        IconData icon,
        Color fg,
        Color bg,
        String title,
        String subtitle,
        int i,
      ) => Reveal(
        index: i,
        offset: 8,
        child: ListTile(
          minTileHeight: 64,
          leading: IconBubble(
            size: 40,
            color: bg,
            child: Icon(icon, color: fg),
          ),
          title: Text(title, style: t.titleSmall),
          subtitle: Text(subtitle, style: t.bodySmall),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.inkFaint,
          ),
          onTap: () {
            Haptics.tap();
            Navigator.pop(ctx, value);
          },
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(s.callName(l.name), style: t.titleLarge),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(PhoneUtils.display(l.phone), style: t.bodyMedium),
              ),
              const SizedBox(height: 12),
              option(
                'ai_call',
                Icons.graphic_eq_rounded,
                AppColors.brand,
                AppColors.brandSoft,
                s.aiCallBy(agentName),
                s.callsTheirPhone,
                0,
              ),
              option(
                'in_app',
                Icons.mic_none_rounded,
                AppColors.ink,
                AppColors.surfaceMuted,
                s.talkInApp(agentName),
                s.voiceTestInApp,
                1,
              ),
              option(
                'sim_call',
                Icons.call_outlined,
                AppColors.ink,
                AppColors.surfaceMuted,
                s.callFromMyPhone,
                s.usesYourSim,
                2,
              ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted || action == null) return false;

  if (action == 'ai_call') {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(SnackBar(content: Text(s.callingName(l.name))));
      await ref.read(callRepoProvider).triggerCall(l.id);
      ref.invalidate(leadCallsProvider(l.id));
      ref.read(dataVersionProvider.notifier).bump();
      Haptics.success();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(s.agentIsCalling(agentName, l.name))),
        );
      return true;
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e, s))));
    }
  } else if (action == 'in_app') {
    context.push('/voice-test');
  } else if (action == 'sim_call') {
    final d = PhoneUtils.normalize(l.phone);
    if (d != null) launchUrl(Uri.parse('tel:+$d'));
  }
  return false;
}

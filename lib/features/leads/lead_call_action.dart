import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
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
    useRootNavigator: true,
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
        int i, {
        bool enabled = true,
      }) => Reveal(
        index: i,
        offset: 8,
        child: ListTile(
          enabled: enabled,
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
                l.enquiryExpired ? s.enquiryTooOld : s.callsTheirPhone,
                0,
                enabled: !l.enquiryExpired,
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
    // Unknown consent (phone contacts, imports): the owner's word first.
    var attested = false;
    if (l.consent == 'unknown') {
      attested = await _confirmAskedToBeContacted(context, l, agentName);
      if (!context.mounted || !attested) return false;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(SnackBar(content: Text(s.callingName(l.name))));
      final calls = ref.read(callRepoProvider);
      try {
        await calls.triggerCall(l.id, consentAttested: attested);
      } on ApiException catch (e) {
        // Our copy of the lead was stale: the backend wants the confirmation.
        if (e.code != 'consent_required' || attested) rethrow;
        messenger.clearSnackBars();
        if (!context.mounted ||
            !await _confirmAskedToBeContacted(context, l, agentName)) {
          return false;
        }
        messenger.showSnackBar(SnackBar(content: Text(s.callingName(l.name))));
        await calls.triggerCall(l.id, consentAttested: true);
      }
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
      final message = e is ApiException && e.code == 'enquiry_expired'
          ? s.enquiryExpiredCall
          : friendlyError(e, s);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  } else if (action == 'in_app') {
    context.push('/voice-test');
  } else if (action == 'sim_call') {
    final d = PhoneUtils.normalize(l.phone);
    if (d != null) launchUrl(Uri.parse('tel:+$d'));
  }
  return false;
}

/// TRAI: an AI call needs a basis. For a lead with unknown consent the owner
/// confirms the customer asked to be contacted in the last 7 days or is
/// already a customer; the backend records it.
Future<bool> _confirmAskedToBeContacted(
  BuildContext context,
  Lead l,
  String agentName,
) async {
  final s = context.s;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(s.askedToBeContacted(l.firstName)),
      content: Text(s.callAttestBody(agentName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(s.cancel),
        ),
        TextButton(
          key: const Key('lead-call-confirm-consent'),
          onPressed: () => Navigator.pop(c, true),
          child: Text(s.yesCallThem),
        ),
      ],
    ),
  );
  return ok == true;
}

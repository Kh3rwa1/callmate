import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../followups/whatsapp_handoff.dart';

/// "NEET · Evening" / "3 BHK · Site visit": interest plus the first
/// attribute, in the UI language where the value is a known option.
String leadInterestLine(S s, Lead l) {
  final first = l.attributes.entries
      .where((e) => e.key != 'budget')
      .map((e) => e.value)
      .firstOrNull;
  final parts = [
    if (l.interest != null && l.interest!.isNotEmpty) s.data(l.interest!),
    if (first != null && first.isNotEmpty) first,
  ];
  return parts.isEmpty ? s.interestUnknown : parts.join(' · ');
}

/// One lead row: avatar, name, one meta line, score, and two quick actions. Rows stack into a single grouped list ([first] / [last]
/// round the outer corners and [last] drops the divider).
class LeadCard extends ConsumerWidget {
  const LeadCard({
    super.key,
    required this.lead,
    this.first = true,
    this.last = true,
  });
  final Lead lead;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final l = lead;
    const r = Radius.circular(AppRadius.card);
    final radius = BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
    final meta = leadInterestLine(s, l);
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label:
            '${l.name}. ${l.score == null ? s.leadStatus(l.status) : s.temperature(l.temperature)}',
        child: Material(
          color: AppColors.surface,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/leads/${l.id}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'lead-avatar-${l.id}',
                        child: LeadAvatar(
                          name: l.name,
                          temperature: l.temperature,
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.name,
                              style: t.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _Status(lead: l),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QuickAction(
                                icon: Icons.chat_outlined,
                                tooltip: s.whatsapp,
                                color: AppColors.whatsapp,
                                onTap: () => _whatsapp(context, ref),
                              ),
                              _QuickAction(
                                icon: Icons.call_outlined,
                                tooltip: s.call,
                                color: AppColors.inkSoft,
                                onTap: () => _call(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!last) const Divider(height: 1, thickness: 1, indent: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _whatsapp(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    List<FollowUp> fus;
    try {
      fus = await ref.read(followUpsProvider.future);
    } catch (_) {
      fus = const [];
    }
    final fu = fus.where((f) => f.leadId == lead.id).firstOrNull;
    if (!context.mounted) return;
    if (fu != null && fu.isPending) {
      unawaited(context.push('/followups/${fu.id}'));
      return;
    }
    // Wait for the business if it hasn't loaded yet (e.g. after a deep link
    // straight to Leads) so the greeting never reads "This is . ".
    String biz;
    try {
      biz = (await ref.read(businessProvider.future))?.name ?? '';
    } catch (_) {
      biz = '';
    }
    if (!context.mounted) return;
    await openWhatsAppHandoff(
      context,
      ref,
      phone: lead.phone,
      message: fu?.message ?? s.waGreeting(lead.firstName, biz),
      followUp: fu,
    );
  }

  Future<void> _call(BuildContext context) async {
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);
    final digits = PhoneUtils.normalize(lead.phone);
    if (digits == null) return;
    final ok = await launchUrl(Uri.parse('tel:+$digits'));
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.callNumber(PhoneUtils.display(lead.phone)))),
      );
    }
  }
}

/// Score badge, or the live status while the lead has no score.
class _Status extends StatelessWidget {
  const _Status({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final Widget child = switch (lead.status) {
      LeadStatus.calling => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            s.onCall,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      LeadStatus.queued => Pill(label: s.queued, dense: true),
      LeadStatus.noAnswer => Pill(label: s.noAnswer, dense: true),
      _ when lead.score == null => Pill(
        label: s.leadStatus(lead.status),
        dense: true,
      ),
      _ => ScoreBadge(score: lead.score),
    };
    return SwapFade(
      child: KeyedSubtree(
        key: ValueKey('${lead.status}-${lead.score?.value}'),
        child: child,
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: () {
      Haptics.tap();
      onTap();
    },
    iconSize: 21,
    color: color,
    constraints: const BoxConstraints.tightFor(width: 42, height: 40),
    padding: EdgeInsets.zero,
    icon: Icon(icon),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../data/models/models.dart';
import '../followups/whatsapp_handoff.dart';

/// One lead row: avatar, name, one meta line, score, and two quiet quick
/// actions. Rows stack into a single grouped list ([first] / [last] round the
/// outer corners and [last] drops the divider).
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
    final t = Theme.of(context).textTheme;
    final l = lead;
    const r = Radius.circular(AppRadius.card);
    final radius = BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
    final meta = l.interestLine;
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label:
            '${l.name}. ${l.score == null ? l.status.label : 'Score ${l.score!.value}, ${l.temperature.label}'}',
        child: Material(
          color: AppColors.surface,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/leads/${l.id}'),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
              decoration: BoxDecoration(
                border: last
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.border, width: 0.8),
                      ),
              ),
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
                        if (meta.isNotEmpty) ...[
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Status(lead: l),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QuickAction(
                            icon: Icons.chat_outlined,
                            tooltip: 'WhatsApp',
                            color: AppColors.whatsapp,
                            onTap: () => _whatsapp(context, ref),
                          ),
                          _QuickAction(
                            icon: Icons.call_outlined,
                            tooltip: 'Call',
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
          ),
        ),
      ),
    );
  }

  Future<void> _whatsapp(BuildContext context, WidgetRef ref) async {
    final fu = (await ref.read(followUpRepoProvider).list())
        .where((f) => f.leadId == lead.id)
        .firstOrNull;
    if (!context.mounted) return;
    if (fu != null && fu.isPending) {
      context.push('/followups/${fu.id}');
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
      message: fu?.message ?? 'Hi ${lead.firstName} 👋\n\nThis is $biz. ',
      followUp: fu,
    );
  }

  Future<void> _call(BuildContext context) async {
    final digits = PhoneUtils.normalize(lead.phone);
    if (digits == null) return;
    final ok = await launchUrl(Uri.parse('tel:+$digits'));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call ${PhoneUtils.display(lead.phone)}')),
      );
    }
  }
}

/// Score badge, or the live status while the lead has no score.
class _Status extends StatelessWidget {
  const _Status({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) => switch (lead.status) {
    LeadStatus.calling => const Pill(
      label: 'On call',
      color: AppColors.success,
      dense: true,
    ),
    LeadStatus.queued => const Pill(label: 'Queued', dense: true),
    LeadStatus.noAnswer => const Pill(label: 'No answer', dense: true),
    _ when lead.score == null => Pill(label: lead.status.label, dense: true),
    _ => ScoreBadge(score: lead.score),
  };
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
    onPressed: onTap,
    iconSize: 20,
    color: color,
    constraints: const BoxConstraints.tightFor(width: 40, height: 36),
    padding: EdgeInsets.zero,
    icon: Icon(icon),
  );
}

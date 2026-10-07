import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../data/models/models.dart';
import '../followups/whatsapp_handoff.dart';

class LeadCard extends ConsumerWidget {
  const LeadCard({super.key, required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final l = lead;
    final live = l.status == LeadStatus.calling;
    return RepaintBoundary(
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        onTap: () => context.push('/leads/${l.id}'),
        semanticLabel:
            '${l.name}. ${l.score == null ? l.status.label : 'Score ${l.score!.value}, ${l.temperature.label}'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LeadAvatar(name: l.name, temperature: l.temperature),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        style: t.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.interestLine,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (live)
                  const Pill(
                    label: 'On call',
                    color: AppColors.success,
                    icon: Icon(
                      Icons.call_rounded,
                      size: 13,
                      color: AppColors.success,
                    ),
                  )
                else if (l.status == LeadStatus.queued)
                  const Pill(label: 'Queued', color: AppColors.brand)
                else if (l.status == LeadStatus.noAnswer)
                  const Pill(label: 'No answer')
                else
                  ScoreBadge(score: l.score),
              ],
            ),
            if (l.summary != null) ...[
              const SizedBox(height: 12),
              Text(
                '“${l.summary!}”',
                style: t.bodyMedium?.copyWith(color: AppColors.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (l.nextAction != NextAction.none) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Next: ',
                    style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Expanded(
                    child: Text(
                      l.nextAction.label,
                      style: t.bodySmall?.copyWith(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _LeadAction(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: AppColors.whatsapp,
                    onTap: () => _whatsapp(context, ref),
                  ),
                ),
                Expanded(
                  child: _LeadAction(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    onTap: () => _call(context),
                  ),
                ),
                Expanded(
                  child: _LeadAction(
                    icon: Icons.chevron_right_rounded,
                    label: 'Details',
                    onTap: () => context.push('/leads/${l.id}'),
                  ),
                ),
              ],
            ),
          ],
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

class _LeadAction extends StatelessWidget {
  const _LeadAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(0, 44),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 19),
    label: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
  );
}

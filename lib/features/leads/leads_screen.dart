import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/lead_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../campaign/campaign_widgets.dart';
import '../followups/whatsapp_handoff.dart';
import 'leads_controller.dart';

/// Leads – "Who should I care about?" (sorted hot → warm → new → cold)
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, this.initialFilter});
  final String? initialFilter;
  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  static const _filters = [
    (LeadFilter.all, 'All'),
    (LeadFilter.newLeads, 'New'),
    (LeadFilter.called, 'Called'),
    (LeadFilter.hot, '🔥 Hot'),
    (LeadFilter.warm, 'Warm'),
    (LeadFilter.callback, 'Callback'),
  ];

  static LeadFilter? parseFilter(String? s) => switch (s) {
    'hot' => LeadFilter.hot,
    'warm' => LeadFilter.warm,
    'new' => LeadFilter.newLeads,
    'called' => LeadFilter.called,
    'callback' => LeadFilter.callback,
    'all' => LeadFilter.all,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _applyInitial();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(leadsListProvider.notifier).loadMore();
      }
    });
  }

  void _applyInitial() {
    final f = parseFilter(widget.initialFilter);
    if (f != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(leadQueryProvider.notifier).setFilter(f));
    }
  }

  @override
  void didUpdateWidget(covariant LeadsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialFilter != widget.initialFilter) _applyInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = ref.watch(leadQueryProvider);
    final s = ref.watch(leadsListProvider);
    final newCount = ref.watch(dashboardProvider).value?.newLeadsReady ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text('Leads', style: t.headlineMedium)),
                  ),
                  IconButton(
                    tooltip: 'Add or import leads',
                    onPressed: () => context.push('/leads/import'),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.page, 12, AppSpace.page, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name, phone or interest',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            ref.read(leadQueryProvider.notifier).setSearch('');
                            setState(() {});
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (v) {
                  setState(() {});
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(leadQueryProvider.notifier).setSearch(v));
                },
              ),
            ),
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.page, vertical: 12),
                children: [
                  for (final (f, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: q.filter == f,
                        labelStyle: TextStyle(fontWeight: FontWeight.w700, color: q.filter == f ? Colors.white : AppColors.inkSoft),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          ref.read(leadQueryProvider.notifier).setFilter(f);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _body(s, q, newCount)),
          ],
        ),
      ),
    );
  }

  Widget _body(PagedState<Lead> s, LeadQuery q, int newCount) {
    if (s.loading && s.items.isEmpty) return const SkeletonList(padding: EdgeInsets.fromLTRB(AppSpace.page, 4, AppSpace.page, 20));
    if (s.error != null && s.items.isEmpty) {
      return ErrorState(message: friendlyError(s.error!), onRetry: () => ref.read(leadsListProvider.notifier).refresh());
    }
    if (s.items.isEmpty) {
      if (q.search.isNotEmpty) {
        return EmptyState(title: 'No matches', message: 'No leads match “${q.search}”.', mascot: MascotState.thinking);
      }
      if (q.filter == LeadFilter.hot) {
        return const EmptyState(
          title: 'No hot leads yet',
          message: 'Your AI employee will flag leads that are ready to buy or book.',
          mascot: MascotState.thinking,
        );
      }
      return EmptyState(
        title: 'No leads here',
        message: 'Your AI employee is ready. Add your first leads to start calling.',
        actionLabel: 'Add leads',
        onAction: () => context.push('/leads/import'),
      );
    }
    final showCta = newCount > 0 && (q.filter == LeadFilter.all || q.filter == LeadFilter.newLeads) && q.search.isEmpty;
    return RefreshIndicator(
      onRefresh: () => ref.read(leadsListProvider.notifier).refresh(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.page, 0, AppSpace.page, 28),
        itemCount: s.items.length + (showCta ? 1 : 0) + 1,
        itemBuilder: (context, i) {
          if (showCta && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CallNewLeadsButton(count: newCount),
            );
          }
          final idx = i - (showCta ? 1 : 0);
          if (idx == s.items.length) {
            return s.hasMore
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : const SizedBox(height: 12);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LeadCard(lead: s.items[idx]),
          );
        },
      ),
    );
  }
}

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
        semanticLabel: '${l.name}. ${l.score == null ? l.status.label : 'Score ${l.score!.value}, ${l.temperature.label}'}',
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
                      Text(l.name, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        l.interestLine,
                        style: t.bodySmall?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (live)
                  const Pill(
                    label: 'On call',
                    color: AppColors.success,
                    icon: Icon(Icons.call_rounded, size: 13, color: AppColors.success),
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
                  Text('Next: ', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      l.nextAction.label,
                      style: t.bodySmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w800),
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
                  child: _LeadAction(icon: Icons.call_rounded, label: 'Call', onTap: () => _call(context)),
                ),
                Expanded(
                  child: _LeadAction(icon: Icons.chevron_right_rounded, label: 'Details', onTap: () => context.push('/leads/${l.id}')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _whatsapp(BuildContext context, WidgetRef ref) async {
    final fu = (await ref.read(followUpRepoProvider).list()).where((f) => f.leadId == lead.id).firstOrNull;
    if (!context.mounted) return;
    if (fu != null && fu.isPending) {
      context.push('/followups/${fu.id}');
      return;
    }
    final biz = ref.read(businessProvider).value?.name ?? '';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call ${PhoneUtils.display(lead.phone)}')));
    }
  }
}

class _LeadAction extends StatelessWidget {
  const _LeadAction({required this.icon, required this.label, required this.onTap, this.color = AppColors.ink});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: color, minimumSize: const Size(0, 44)),
    onPressed: onTap,
    icon: Icon(icon, size: 19),
    label: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    ),
  );
}

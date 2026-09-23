import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../models/bootstrap.dart';
import '../../models/call.dart';
import '../../models/contact.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../calls/start_calling_screen.dart';
import '../customer/customer_detail_screen.dart';
import '../live_call/live_call_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final data = repo.data;
    final stats = repo.stats;

    if (repo.isLoading && data.contacts.isEmpty) {
      return const Center(child: LoadingBlock(label: 'Waking up your AI…'));
    }

    if (repo.error != null && data.contacts.isEmpty && !repo.isLoading) {
      return Center(
        child: ErrorBlock(
          title: "We couldn't reach your dashboard",
          message: repo.error!,
          onRetry: () => context.read<AppRepository>().load(),
        ),
      );
    }

    final attention = contactsNeedingAttention(data.contacts, 3);
    final liveCalls = data.calls.where((c) => c.isLive).toList();
    final liveCall = liveCalls.isEmpty ? null : liveCalls.first;
    final agent = data.agent;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () => context.read<AppRepository>().load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 32),
          children: [
            Text(
              'Good day',
              style: AppText.caption.copyWith(color: AppColors.inkSoft),
            ),
            Text(data.organisation.name, style: AppText.hero),

            const SizedBox(height: AppSpacing.lg),

            _AiEmployeeCard(
              active: agent?.inboundEnabled ?? true,
              activeCalls: stats.activeCalls,
              liveCall: liveCall,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => const AiActivitySheet(),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Calls',
                    value: '${stats.totalCalls}',
                    tone: Tone.blue,
                    icon: Icons.phone_in_talk_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Metric(
                    label: 'Booked',
                    value: '${stats.bookedCount}',
                    tone: Tone.green,
                    icon: Icons.event_available_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Metric(
                    label: 'Recovered',
                    value: formatCompactCurrency(stats.recoveredAmount),
                    tone: Tone.purple,
                    icon: Icons.savings_rounded,
                  ),
                ),
              ],
            ),

            if (attention.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Needs attention',
                action: TextButton(
                  onPressed: () => context.open(const PipelineScreen()),
                  child: Text('View all', style: AppText.caption.copyWith(color: AppColors.brand)),
                ),
              ),
              for (final contact in attention)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _AttentionRow(
                    contact: contact,
                    onTap: () => context.open(CustomerDetailScreen(contactId: contact.id)),
                  ),
                ),
            ],

            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Start calling',
                icon: Icons.phone_forwarded_rounded,
                onPressed: () => context.open(const StartCallingScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiEmployeeCard extends StatelessWidget {
  const _AiEmployeeCard({
    required this.active,
    required this.activeCalls,
    this.liveCall,
    required this.onTap,
  });

  final bool active;
  final int activeCalls;
  final Call? liveCall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Mascot(mood: MascotMood.happy, size: 58),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI EMPLOYEE',
                      style: AppText.label.copyWith(color: AppColors.inkSoft),
                    ),
                    Text(agentName, style: AppText.title),
                  ],
                ),
              ),
              StatusPill(
                label: active ? 'Working' : 'Paused',
                tone: active ? Tone.green : Tone.neutral,
                icon: active ? Icons.bolt_rounded : Icons.pause_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                '$activeCalls',
                style: AppText.hero.copyWith(color: AppColors.brand),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  activeCalls == 1 ? 'call active now' : 'calls active now',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ),
              if (liveCall != null)
                TextButton(
                  onPressed: () => context.open(LiveCallScreen(callId: liveCall!.id)),
                  child: Text(
                    'Take over',
                    style: AppText.caption.copyWith(color: AppColors.blue),
                  ),
                )
              else
                TextButton(
                  onPressed: onTap,
                  child: Text(
                    'View activity',
                    style: AppText.caption.copyWith(color: AppColors.blue),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short summary of what the employee has been doing, shown from the AI card.
class AiActivitySheet extends StatelessWidget {
  const AiActivitySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppRepository>().data;
    final recent = data.calls.take(6).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$agentName has been busy', style: AppText.title),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your AI employee answers every call, follows up on WhatsApp and books '
            'customers while you run the business.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (recent.isEmpty)
            Text('No calls yet.', style: AppText.caption.copyWith(color: AppColors.inkSoft))
          else
            for (final call in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    IconTile(
                      icon: Icons.call_rounded,
                      tone: call.outcome == CallOutcome.booked ? Tone.green : Tone.blue,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.contactById(call.contactId)?.name ?? 'Customer',
                            style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            call.outcome?.label ?? call.status.label,
                            style: AppText.caption.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Close',
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final Tone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, tone: tone, size: 34),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: AppText.title),
          Text(label, style: AppText.label.copyWith(color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (contact.status) {
      ContactStatus.followUp => Tone.amber,
      ContactStatus.booked => Tone.green,
      ContactStatus.recovered => Tone.purple,
      ContactStatus.noResponse => Tone.coral,
      _ => Tone.neutral,
    };

    return SurfaceCard(
      radius: AppRadius.xl,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ContactAvatar(initials: contact.initials, colorHex: contact.avatarColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                Text(contact.service, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
              ],
            ),
          ),
          StatusPill(label: contact.status.label, tone: tone),
        ],
      ),
    );
  }
}

/// Formats money the way the backend reports it (Indian rupees, compact).
String formatCompactCurrency(double amount) {
  if (amount <= 0) return '₹0';
  if (amount >= 10000000) return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
  if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(1)}L';
  if (amount >= 1000) return '₹${(amount / 1000).toStringAsFixed(1)}K';
  return '₹${amount.toStringAsFixed(0)}';
}

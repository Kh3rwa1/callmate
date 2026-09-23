import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_repository.dart';
import '../../models/call.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../call_result/call_result_screen.dart';
import '../live_call/live_call_screen.dart';
import 'start_calling_screen.dart';

enum CallFilter { all, active, completed, missed }

extension on CallFilter {
  String get label => switch (this) {
        CallFilter.all => 'All',
        CallFilter.active => 'Active',
        CallFilter.completed => 'Completed',
        CallFilter.missed => 'Missed',
      };

  bool matches(Call call) => switch (this) {
        CallFilter.all => true,
        CallFilter.active => call.isLive,
        CallFilter.completed => call.status == CallStatus.completed,
        CallFilter.missed =>
          call.status == CallStatus.missed || call.status == CallStatus.failed,
      };
}

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  CallFilter _filter = CallFilter.all;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final calls = repo.data.calls.where(_filter.matches).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Calls', style: AppText.hero),
                      Text(
                        '${repo.data.calls.length} calls handled by $agentName',
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
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: CallFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final filter = CallFilter.values[index];
                final selected = filter == _filter;
                return Material(
                  color: selected ? AppColors.ink : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _filter = filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: selected ? AppColors.ink : AppColors.border),
                      ),
                      child: Text(
                        filter.label,
                        style: AppText.caption.copyWith(
                          color: selected ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          Expanded(
            child: repo.isLoading && repo.data.calls.isEmpty
                ? const Center(child: LoadingBlock(label: 'Loading your calls…'))
                : calls.isEmpty
                    ? Center(
                        child: EmptyBlock(
                          title: 'No calls here',
                          message: 'Start a calling round and $agentName will begin working through your list.',
                          actionLabel: 'Start calling',
                          onAction: () => context.open(const StartCallingScreen()),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.brand,
                        onRefresh: () => context.read<AppRepository>().load(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, 0, AppSpacing.lg, 32),
                          itemCount: calls.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final call = calls[index];
                            final contact = repo.data.contactById(call.contactId);
                            return CallRow(
                              call: call,
                              contactName: contact?.name ?? 'Customer',
                              initials: contact?.initials ?? '?',
                              colorHex: contact?.avatarColor ?? '#18C97A',
                              onTap: () => context.open(
                                call.isLive
                                    ? LiveCallScreen(callId: call.id)
                                    : CallResultScreen(callId: call.id),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// One row in the call history.
class CallRow extends StatelessWidget {
  const CallRow({
    super.key,
    required this.call,
    required this.contactName,
    required this.initials,
    required this.colorHex,
    this.onTap,
  });

  final Call call;
  final String contactName;
  final String initials;
  final String colorHex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (call.outcome) {
      CallOutcome.booked => Tone.green,
      CallOutcome.recovered => Tone.green,
      CallOutcome.interested => Tone.purple,
      CallOutcome.followUp => Tone.amber,
      CallOutcome.noResponse => Tone.coral,
      _ => call.isLive ? Tone.blue : Tone.neutral,
    };

    return SurfaceCard(
      onTap: onTap,
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ContactAvatar(initials: initials, colorHex: colorHex, size: 44),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contactName,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  call.summary.isEmpty ? call.status.label : call.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusPill(
            label: call.isLive ? 'Live' : (call.outcome?.label ?? call.status.label),
            tone: tone,
          ),
        ],
      ),
    );
  }
}

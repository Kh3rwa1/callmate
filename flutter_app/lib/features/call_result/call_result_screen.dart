import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/call.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../customer/customer_detail_screen.dart';

/// The result of one finished call.
///
/// The transcript is loaded here on demand — it is never bundled with the call
/// list, which keeps the call history light.
class CallResultScreen extends StatefulWidget {
  const CallResultScreen({super.key, required this.callId});

  final String callId;

  @override
  State<CallResultScreen> createState() => _CallResultScreenState();
}

class _CallResultScreenState extends State<CallResultScreen> {
  Future<Transcript>? _transcript;

  @override
  void initState() {
    super.initState();
    _transcript = context.read<AppRepository>().transcript(widget.callId);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final call = repo.data.callById(widget.callId);
    final contact = call == null ? null : repo.data.contactById(call.contactId);

    if (call == null) {
      return PageScaffold(
        title: 'Call result',
        child: EmptyBlock(
          title: 'This call is no longer available',
          message: 'It may have been removed from your history.',
        ),
      );
    }

    final tone = switch (call.outcome) {
      CallOutcome.booked || CallOutcome.recovered => Tone.green,
      CallOutcome.interested => Tone.purple,
      CallOutcome.followUp => Tone.amber,
      CallOutcome.noResponse => Tone.coral,
      _ => Tone.neutral,
    };

    return PageScaffold(
      title: 'Call result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Mascot(
                  mood: call.outcome == CallOutcome.booked
                      ? MascotMood.celebrating
                      : MascotMood.happy,
                  size: 84,
                ),
                const SizedBox(height: AppSpacing.md),
                StatusPill(
                  label: call.outcome?.label ?? call.status.label,
                  tone: tone,
                  large: true,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  contact?.name ?? 'Customer',
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  call.summary.isEmpty ? 'Call finished' : call.summary,
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'Duration',
                  value: _formatDuration(call.durationSeconds),
                  tone: Tone.blue,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _InfoTile(
                  label: 'Direction',
                  value: call.direction == 'inbound' ? 'Inbound' : 'Outbound',
                  tone: Tone.purple,
                ),
              ),
            ],
          ),

          if (call.insight.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SurfaceCard(
              color: AppColors.purpleSoft,
              borderColor: AppColors.purple.withOpacity(0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$agentName'S SUMMARY",
                    style: AppText.label.copyWith(color: AppColors.purple),
                  ),
                  const SizedBox(height: 6),
                  Text(call.insight, style: AppText.body),
                ],
              ),
            ),
          ],

          if (contact != null && contact.appointment != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SurfaceCard(
              child: Row(
                children: [
                  const IconTile(icon: Icons.event_available_rounded, tone: Tone.green),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Appointment', style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                        Text(
                          '${contact.appointment!.date} · ${contact.appointment!.time}',
                          style: AppText.caption.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Transcript'),
          _TranscriptView(future: _transcript!, onRetry: () {
            setState(() {
              _transcript = context.read<AppRepository>().transcript(widget.callId);
            });
          }),

          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'View customer',
            icon: Icons.person_rounded,
            onPressed: contact == null
                ? null
                : () => context.open(CustomerDetailScreen(contactId: contact.id)),
          ),
        ],
      ),
    );
  }
}

class _TranscriptView extends StatelessWidget {
  const _TranscriptView({required this.future, required this.onRetry});

  final Future<Transcript> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Transcript>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingBlock(label: 'Loading the conversation…');
        }
        if (snapshot.hasError) {
          final message =
              snapshot.error is ApiException ? '${snapshot.error}' : 'We could not load it.';
          return ErrorBlock(
            title: "We couldn't load the transcript",
            message: message,
            onRetry: onRetry,
          );
        }

        final turns = snapshot.data?.turns ?? const [];
        if (turns.isEmpty) {
          return Text(
            'No transcript was recorded for this call.',
            style: AppText.caption.copyWith(color: AppColors.inkSoft),
          );
        }

        return Column(
          children: [
            for (final turn in turns)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Align(
                  alignment: turn.isAi ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: turn.isAi ? AppColors.secondary : AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          turn.isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        Text(
                          turn.isAi ? agentName : 'Customer',
                          style: AppText.label.copyWith(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 3),
                        Text(turn.text, style: AppText.caption.copyWith(color: AppColors.ink)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppText.label.copyWith(color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          Text(value, style: AppText.body.copyWith(color: tone.foreground, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0:00';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

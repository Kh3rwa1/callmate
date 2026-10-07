import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';

/// Clean conversational transcript (AI employee on the left, lead on the right).
class TranscriptView extends StatefulWidget {
  const TranscriptView({
    super.key,
    required this.transcript,
    required this.leadName,
    this.agentName = 'AI',
    this.maxLines,
  });
  final CallTranscript transcript;
  final String leadName;
  final String agentName;
  final int? maxLines;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.transcript.lines;
    final limit = widget.maxLines;
    final shown = (!_expanded && limit != null && lines.length > limit)
        ? lines.take(limit).toList()
        : lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in shown)
          TranscriptBubble(
            isAgent: l.speaker == TranscriptSpeaker.agent,
            text: l.text,
            who: l.speaker == TranscriptSpeaker.agent
                ? widget.agentName
                : widget.leadName,
            at: l.offset,
          ),
        if (shown.length < lines.length)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text('Show full transcript (${lines.length} lines)'),
          ),
      ],
    );
  }
}

class TranscriptBubble extends StatelessWidget {
  const TranscriptBubble({
    super.key,
    required this.isAgent,
    required this.text,
    required this.who,
    this.at,
    this.pending = false,
  });
  final bool isAgent;
  final String text;
  final String who;
  final Duration? at;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isAgent ? AppColors.brandSoft : AppColors.surfaceMuted,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isAgent ? 4 : 18),
            bottomRight: Radius.circular(isAgent ? 18 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  who,
                  style: t.labelMedium?.copyWith(
                    color: isAgent ? AppColors.brand : AppColors.inkSoft,
                    fontSize: 12,
                  ),
                ),
                if (at != null)
                  Text(
                    '  ${Fmt.duration(at!)}',
                    style: t.bodySmall?.copyWith(fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              text,
              style: t.bodyMedium?.copyWith(
                color: AppColors.ink,
                fontStyle: pending ? FontStyle.italic : null,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: '$who said: $text',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: isAgent
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: isAgent
                ? [
                    const MascotAvatar(size: 30),
                    const SizedBox(width: 8),
                    bubble,
                    const SizedBox(width: 40),
                  ]
                : [const SizedBox(width: 40), bubble],
          ),
        ),
      ),
    );
  }
}

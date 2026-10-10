import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/mascot.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// Clean conversational transcript (AI employee on the left, lead on the
/// right). Expanding grows the card smoothly instead of jumping.
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
    final s = context.s;
    final lines = widget.transcript.lines;
    final limit = widget.maxLines;
    final shown = (!_expanded && limit != null && lines.length > limit)
        ? lines.take(limit).toList()
        : lines;
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: Column(
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
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                onPressed: () {
                  Haptics.tap();
                  setState(() => _expanded = true);
                },
                child: Text(s.showFullTranscript(lines.length)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One chat bubble. With [animate] it grows in from its speaker's side the
/// first time it appears (used for the live voice test).
class TranscriptBubble extends StatelessWidget {
  const TranscriptBubble({
    super.key,
    required this.isAgent,
    required this.text,
    required this.who,
    this.at,
    this.pending = false,
    this.animate = false,
  });
  final bool isAgent;
  final String text;
  final String who;
  final Duration? at;
  final bool pending;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final bubble = Flexible(
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.base),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                Flexible(
                  child: Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelMedium?.copyWith(
                      color: isAgent ? AppColors.brand : AppColors.inkSoft,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (at != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    Fmt.duration(at!),
                    style: t.bodySmall?.copyWith(
                      fontSize: 11,
                      color: AppColors.inkFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppMotion.of(context, AppMotion.base),
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: pending ? AppColors.inkSoft : AppColors.ink,
                height: 1.4,
              ),
              child: Text(text),
            ),
          ],
        ),
      ),
    );
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isAgent
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isAgent
            ? [
                const MascotAvatar(size: 26),
                const SizedBox(width: 8),
                bubble,
                const SizedBox(width: 40),
              ]
            : [const SizedBox(width: 40), bubble],
      ),
    );
    if (animate) row = _GrowIn(fromLeft: isAgent, child: row);
    return Semantics(
      label: s.said(who, text),
      child: ExcludeSemantics(child: row),
    );
  }
}

class _GrowIn extends StatefulWidget {
  const _GrowIn({required this.fromLeft, required this.child});
  final bool fromLeft;
  final Widget child;

  @override
  State<_GrowIn> createState() => _GrowInState();
}

class _GrowInState extends State<_GrowIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed) return;
    if (AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      final v = AppMotion.emphasized.transform(_c.value);
      return Opacity(
        opacity: _c.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.86 + 0.14 * v,
          alignment: widget.fromLeft
              ? Alignment.bottomLeft
              : Alignment.bottomRight,
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

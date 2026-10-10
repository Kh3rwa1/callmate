import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Motion tokens. One vocabulary for every animation in the app, so timing
/// feels consistent. Everything collapses to instant when the OS asks for
/// reduced motion ([AppMotion.reduced]).
///
/// Rules the app follows:
/// * Motion explains a change (what appeared, where it went, what it means).
/// * Entrances play once; nothing re-animates while scrolling.
/// * Nothing idles in a loop unless it shows something live (a call, a voice).
class AppMotion {
  const AppMotion._();

  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const page = Duration(milliseconds: 360);

  /// Material 3 "emphasized decelerate": quick start, long soft landing.
  static const emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const exit = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Slight overshoot for things that "pop" into place.
  static const pop = Cubic(0.34, 1.4, 0.64, 1.0);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Spring presets (mass 1). Springs keep their velocity when interrupted,
/// which is what makes presses and toggles feel physical.
class AppSprings {
  const AppSprings._();

  /// Press-in: fast, no bounce.
  static final press = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 900,
    ratio: 1,
  );

  /// Release: a small, quick overshoot.
  static final release = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.48,
  );

  /// Things settling into place (indicators, badges).
  static final settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 260,
    ratio: 0.72,
  );
}

/// Scales its child down while pressed and springs back (with a little
/// overshoot) on release – the tactile "squish" of a physical button.
///
/// The squish listens to raw pointer events, so it never competes with a
/// Material button inside it: wrap a button with `onTap: null` for feedback
/// only, or give [onTap] to make the child itself tappable.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent _) {
    if (!widget.enabled || AppMotion.reduced(context)) return;
    _c.animateWith(SpringSimulation(AppSprings.press, _c.value, 1, 0));
  }

  void _up(PointerEvent _) {
    if (!mounted || (_c.value == 0 && !_c.isAnimating)) return;
    _c.animateWith(
      SpringSimulation(AppSprings.release, _c.value, 0, _c.velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 - (1 - widget.scale) * _c.value,
        child: child,
      ),
      child: widget.child,
    );
    if (widget.onTap != null || widget.onLongPress != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled && widget.onTap != null
            ? () {
                if (widget.haptic) Haptics.tap();
                widget.onTap!();
              }
            : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: child,
      );
    }
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: child,
    );
  }
}

/// Remembers which [Reveal] ids already played, so list rows that scroll
/// out and back in (and are rebuilt) appear instantly instead of animating
/// again.
class RevealMemory {
  RevealMemory._();
  static final _seen = <Object>{};

  static bool seen(Object id) => _seen.contains(id);

  static void mark(Object id) {
    if (_seen.length > 4000) _seen.clear();
    _seen.add(id);
  }

  @visibleForTesting
  static void clear() => _seen.clear();
}

/// Fades and lifts its child into place once, after [index] × stagger.
/// Use on page sections and the first rows of a list.
///
/// Give list rows an [id]: a row that already played shows instantly when
/// it is rebuilt (scrolling back, refreshes).
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.id,
    this.offset = 18,
    this.duration = const Duration(milliseconds: 560),
    this.stagger = const Duration(milliseconds: 60),
    this.maxDelayed = 8,
  });

  final Widget child;
  final int index;
  final Object? id;
  final double offset;
  final Duration duration;
  final Duration stagger;

  /// Items beyond this index appear together (long lists stay snappy).
  final int maxDelayed;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: AppMotion.emphasized,
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed || _delay != null) return;
    final id = widget.id;
    if (AppMotion.reduced(context) || (id != null && RevealMemory.seen(id))) {
      _c.value = 1;
      return;
    }
    if (id != null) RevealMemory.mark(id);
    final steps = widget.index.clamp(0, widget.maxDelayed);
    final delay = widget.stagger * steps;
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    // Same widget structure at every frame: swapping it when the reveal
    // ends would remount the child and drop its state.
    builder: (_, child) {
      final v = _t.value.clamp(0.0, 1.0);
      // Opacity leads slightly so the lift and settle read as one gesture.
      return Opacity(
        opacity: Curves.easeOut.transform(v),
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - v)),
          child: Transform.scale(scale: 0.98 + 0.02 * v, child: child),
        ),
      );
    },
    child: widget.child,
  );
}

/// Counts to [value] whenever it changes, in tabular figures so the width
/// never jitters. With [countUp] it also counts up from zero on first show.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.format,
    this.countUp = false,
    this.duration = const Duration(milliseconds: 900),
  });

  final num value;
  final TextStyle? style;
  final String Function(int)? format;
  final bool countUp;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: countUp ? 0.0 : null, end: value.toDouble()),
      duration: AppMotion.of(context, duration),
      curve: Curves.easeOutExpo,
      builder: (_, v, _) {
        final n = v.round();
        return Text(format?.call(n) ?? '$n', style: s);
      },
    );
  }
}

/// Crossfades + slightly scales between children when [child]'s key changes.
class SwapFade extends StatelessWidget {
  const SwapFade({super.key, required this.child, this.duration});
  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.of(context, duration ?? AppMotion.base),
    switchInCurve: AppMotion.emphasized,
    switchOutCurve: AppMotion.exit,
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(a),
        child: child,
      ),
    ),
    child: child,
  );
}

/// Swaps icons/badges with a springy pop (new child scales up from 0.4).
class PopSwitcher extends StatelessWidget {
  const PopSwitcher({super.key, required this.child, this.duration});
  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.of(context, duration ?? AppMotion.slow),
    reverseDuration: AppMotion.of(context, AppMotion.fast),
    // The switcher's own curves stay linear so `a` never leaves 0..1 (an
    // overshooting curve here would feed values > 1 into the Interval
    // below and assert). The overshoot is applied to the scale only.
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a.drive(CurveTween(curve: const Interval(0, 0.5))),
      child: ScaleTransition(
        scale: a.drive(
          Tween(begin: 0.4, end: 1.0).chain(CurveTween(curve: AppMotion.pop)),
        ),
        child: child,
      ),
    ),
    child: child,
  );
}

/// Shared-axis (X) transition: the new page slides in from the right while
/// fading in; the page underneath slides left and fades out. Reads as
/// "forward" and keeps spatial sense through every push.
Widget sharedAxisTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (AppMotion.reduced(context)) return child;
  final inT = CurvedAnimation(
    parent: animation,
    curve: AppMotion.emphasized,
    reverseCurve: AppMotion.emphasized.flipped,
  );
  final outT = CurvedAnimation(
    parent: secondaryAnimation,
    curve: AppMotion.standard,
    reverseCurve: AppMotion.standard.flipped,
  );
  return AnimatedBuilder(
    animation: Listenable.merge([inT, outT]),
    builder: (context, c) {
      final enter = inT.value;
      final leave = outT.value;
      final enterFade = ((enter - 0.15) / 0.55).clamp(0.0, 1.0);
      final leaveFade = 1 - (leave / 0.35).clamp(0.0, 1.0);
      return Opacity(
        opacity: enterFade * (0.15 + 0.85 * leaveFade),
        child: Transform.translate(
          offset: Offset(36 * (1 - enter) - 28 * leave, 0),
          child: c,
        ),
      );
    },
    child: child,
  );
}

/// Fade-through: the new screen fades in while growing from 96%. Used where
/// there is no spatial "forward" (sign-in → home, splash → app). When a page
/// is pushed on top, it leaves the same way shared-axis pages do.
Widget fadeThroughTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (AppMotion.reduced(context)) return child;
  final inT = CurvedAnimation(parent: animation, curve: AppMotion.emphasized);
  final outT = CurvedAnimation(
    parent: secondaryAnimation,
    curve: AppMotion.standard,
    reverseCurve: AppMotion.standard.flipped,
  );
  return AnimatedBuilder(
    animation: Listenable.merge([inT, outT]),
    builder: (context, c) {
      final enter = inT.value;
      final leave = outT.value;
      final fadeIn = ((animation.value - 0.25) / 0.75).clamp(0.0, 1.0);
      final leaveFade = 1 - (leave / 0.35).clamp(0.0, 1.0);
      return Opacity(
        opacity: Curves.easeOut.transform(fadeIn) * (0.15 + 0.85 * leaveFade),
        child: Transform.translate(
          offset: Offset(-28 * leave, 0),
          child: Transform.scale(scale: 0.96 + 0.04 * enter, child: c),
        ),
      );
    },
    child: child,
  );
}

/// [PageTransitionsBuilder] for plain Material routes (shared axis).
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => sharedAxisTransition(context, animation, secondaryAnimation, child);
}

/// Hosts the bottom-tab branches: only the active branch is on stage, and
/// switching tabs fades through (old out fast, new in with a small rise).
/// Inactive branches keep their state but stop their tickers.
class FadeThroughBranches extends StatefulWidget {
  const FadeThroughBranches({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;

  @override
  State<FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  int? _from;

  @override
  void didUpdateWidget(covariant FadeThroughBranches old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (AppMotion.reduced(context)) {
        _from = null;
        _c.value = 1;
      } else {
        _from = old.index;
        _c.forward(from: 0).whenCompleteOrCancel(() {
          if (mounted) setState(() => _from = null);
        });
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [for (var i = 0; i < widget.children.length; i++) _branch(i)],
    );
  }

  Widget _branch(int i) {
    final active = i == widget.index;
    final leaving = i == _from;
    // One fixed structure per branch (Offstage › IgnorePointer › Opacity ›
    // Transform) so switching tabs never remounts a branch's navigator.
    return Offstage(
      offstage: !active && !leaving,
      child: TickerMode(
        enabled: active,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, c) {
            final t = _c.value;
            var opacity = 1.0;
            var dy = 0.0;
            if (leaving) {
              opacity = 1 - (t / 0.35).clamp(0.0, 1.0);
            } else if (_from != null && t < 1) {
              final inT = AppMotion.emphasized.transform(
                ((t - 0.25) / 0.75).clamp(0.0, 1.0),
              );
              opacity = inT;
              dy = 10 * (1 - inT);
            }
            return IgnorePointer(
              ignoring: leaving,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(offset: Offset(0, dy), child: c),
              ),
            );
          },
          child: widget.children[i],
        ),
      ),
    );
  }
}

/// Light haptics in one place (so they can be tuned or disabled together).
class Haptics {
  const Haptics._();
  static void tap() => HapticFeedback.selectionClick();
  static void press() => HapticFeedback.lightImpact();
  static void success() => HapticFeedback.mediumImpact();
  static void warn() => HapticFeedback.heavyImpact();
}

/// A gentle idle bob, for illustrations on calm screens (empty states,
/// sign-in). Off under reduced motion.
class FloatIdle extends StatefulWidget {
  const FloatIdle({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.period = const Duration(milliseconds: 3200),
  });
  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<FloatIdle> createState() => _FloatIdleState();
}

class _FloatIdleState extends State<FloatIdle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
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
    builder: (_, child) => Transform.translate(
      offset: Offset(
        0,
        -widget.amplitude * Curves.easeInOut.transform(_c.value),
      ),
      child: child,
    ),
    child: widget.child,
  );
}

/// Scales + fades its child in once, with a springy overshoot.
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
  });
  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed || _t != null) return;
    if (AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      final v = _c.value;
      return Opacity(
        opacity: (v * 2).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: v >= 1 ? 1 : 0.6 + 0.4 * AppMotion.pop.transform(v),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

/// The "done" moment: a filled circle pops in, then a check draws itself.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({
    super.key,
    this.size = 72,
    this.color,
    this.checkColor = Colors.white,
  });
  final double size;
  final Color? color;
  final Color checkColor;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed) return;
    if (AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
      Haptics.success();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final circle = AppMotion.pop.transform((t / 0.5).clamp(0.0, 1.0));
          final stroke = Curves.easeOutCubic.transform(
            ((t - 0.35) / 0.65).clamp(0.0, 1.0),
          );
          return SizedBox.square(
            dimension: widget.size,
            child: Transform.scale(
              scale: circle,
              child: CustomPaint(
                painter: _CheckPainter(
                  color: color,
                  check: widget.checkColor,
                  progress: stroke,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.color,
    required this.check,
    required this.progress,
  });
  final Color color;
  final Color check;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawCircle(size.center(Offset.zero), w / 2, Paint()..color = color);
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(w * 0.29, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.72, w * 0.37);
    final metric = path.computeMetrics().first;
    final part = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      part,
      Paint()
        ..color = check
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color || old.check != check;
}

/// Reveals a sentence word by word, like it is being understood. Layout is
/// fixed from the first frame (words only fade in), so nothing reflows.
class WordReveal extends StatefulWidget {
  const WordReveal(
    this.text, {
    super.key,
    this.style,
    this.perWord = const Duration(milliseconds: 28),
    this.maxDuration = const Duration(milliseconds: 1100),
  });
  final String text;
  final TextStyle? style;
  final Duration perWord;
  final Duration maxDuration;

  @override
  State<WordReveal> createState() => _WordRevealState();
}

class _WordRevealState extends State<WordReveal>
    with SingleTickerProviderStateMixin {
  late final List<String> _words = RegExp(
    r'\S+\s*',
  ).allMatches(widget.text).map((m) => m.group(0)!).toList();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: math.min(
        widget.maxDuration.inMilliseconds,
        widget.perWord.inMilliseconds * _words.length + 260,
      ),
    ),
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
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    final color = base.color ?? Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value;
        if (t >= 1 || _words.isEmpty) {
          return Text(widget.text, style: widget.style);
        }
        final n = _words.length;
        // Each word fades over ~25% of the run, starting staggered.
        const fade = 0.25;
        return Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < n; i++)
                TextSpan(
                  text: _words[i],
                  style: TextStyle(
                    color: color.withValues(
                      alpha:
                          color.a *
                          ((t - (i / n) * (1 - fade)) / fade).clamp(0.0, 1.0),
                    ),
                  ),
                ),
            ],
          ),
          style: widget.style,
        );
      },
    );
  }
}

/// Three dots bouncing in turn: "thinking…".
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color, this.size = 7});
  final Color? color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 0.3),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    -widget.size *
                        0.7 *
                        math.max(
                          0,
                          math.sin((_c.value * 2 * math.pi) - i * 0.9),
                        ),
                  ),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One-shot confetti burst from the centre of its box. Decorative only;
/// skipped entirely under reduced motion.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.size = 220,
    this.count = 28,
    this.colors = const [
      Color(0xFFD92D35),
      Color(0xFFF59E0B),
      Color(0xFF0562FD),
      Color(0xFF22A55A),
      Color(0xFF0EA5E9),
      Color(0xFFFD8BB2),
    ],
  });
  final double size;
  final int count;
  final List<Color> colors;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final List<_Bit> _bits = List.generate(widget.count, (i) {
    final angle = (i / widget.count) * 6.283 + (i.isEven ? 0.15 : -0.1);
    final speed = 0.55 + (i * 37 % 45) / 100;
    return _Bit(
      angle: angle,
      speed: speed,
      color: widget.colors[i % widget.colors.length],
      spin: (i % 5 - 2) * 2.5,
      wide: i % 3 == 0,
    );
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed && !AppMotion.reduced(context)) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => _c.isAnimating
              ? CustomPaint(painter: _ConfettiPainter(_bits, _c.value))
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

class _Bit {
  const _Bit({
    required this.angle,
    required this.speed,
    required this.color,
    required this.spin,
    required this.wide,
  });
  final double angle;
  final double speed;
  final Color color;
  final double spin;
  final bool wide;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final out = Curves.easeOutCubic.transform(t);
    final r = size.width / 2;
    for (final b in bits) {
      final dist = r * b.speed * out;
      final gravity = 60 * t * t;
      final p =
          c +
          Offset(dist * math.cos(b.angle), dist * math.sin(b.angle) + gravity);
      final paint = Paint()
        ..color = b.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(b.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: b.wide ? 9 : 5,
            height: b.wide ? 5 : 9,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Shakes its child sideways whenever [trigger] changes – "that's not
/// right" for a form that failed validation. Pair with [Haptics.warn].
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  /// Bump this (e.g. a counter) to play the shake once.
  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !AppMotion.reduced(context)) {
      _c.forward(from: 0);
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
      final t = _c.value;
      // Three decaying swings.
      final dx = math.sin(t * math.pi * 6) * 9 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// Soft rings expanding out from behind its child, like a ringing phone or
/// a mind at work. Shows only while something is live; static under
/// reduced motion.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.child,
    required this.size,
    this.color,
    this.rings = 3,
    this.period = const Duration(milliseconds: 2400),
  });
  final Widget child;

  /// Diameter the outermost ring reaches.
  final double size;
  final Color? color;
  final int rings;
  final Duration period;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: _RingsPainter(
                      t: _c.isAnimating ? _c.value : -1,
                      rings: widget.rings,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.rings, required this.color});

  /// Loop position 0..1, or negative for "not animating".
  final double t;
  final int rings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t < 0) return;
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < rings; i++) {
      final p = (t + i / rings) % 1.0;
      final r = maxR * (0.45 + 0.55 * Curves.easeOutCubic.transform(p));
      final alpha = 0.22 * (1 - p);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t || old.color != color || old.rings != rings;
}

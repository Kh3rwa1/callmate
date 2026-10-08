import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion tokens. One vocabulary for every animation in the app, so timing
/// feels consistent. Everything collapses to instant when the OS asks for
/// reduced motion ([AppMotion.reduced]).
class AppMotion {
  const AppMotion._();

  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const page = Duration(milliseconds: 380);

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

/// Scales its child down while pressed and springs back on release – the
/// tactile "squish" of a physical button.
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    reverseDuration: const Duration(milliseconds: 360),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent _) {
    if (!widget.enabled || AppMotion.reduced(context)) return;
    _c.forward();
  }

  void _up(PointerEvent _) {
    if (mounted && _c.value > 0) _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.status == AnimationStatus.reverse
            ? AppMotion.pop.transform(_c.value)
            : AppMotion.standard.transform(_c.value);
        return Transform.scale(scale: 1 - (1 - widget.scale) * t, child: child);
      },
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

/// Fades and lifts its child into place once, after [index] × stagger.
/// Use on list items and page sections for a choreographed entrance.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
    this.duration = const Duration(milliseconds: 460),
    this.stagger = const Duration(milliseconds: 45),
    this.maxDelayed = 8,
  });

  final Widget child;
  final int index;
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
    if (AppMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
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
    builder: (_, child) => Opacity(
      opacity: _t.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _t.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// Counts up (or down) to [value] whenever it changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.format,
    this.duration = const Duration(milliseconds: 900),
  });

  final num value;
  final TextStyle? style;
  final String Function(int)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: AppMotion.of(context, duration),
    curve: Curves.easeOutExpo,
    builder: (_, v, _) {
      final n = v.round();
      return Text(format?.call(n) ?? '$n', style: style);
    },
  );
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

/// Page transition: incoming page fades in while sliding up a few pixels and
/// settling from 98% scale; the outgoing page dims back. Feels native on
/// Android without the default zoom.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    final inT = CurvedAnimation(
      parent: animation,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.exit,
    );
    final outT = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.standard,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([inT, outT]),
      builder: (context, c) {
        final enter = inT.value;
        final leave = outT.value;
        return Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - enter)),
            child: Transform.scale(
              scale: (0.985 + 0.015 * enter) * (1 - 0.03 * leave),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.06 * leave),
                  BlendMode.srcATop,
                ),
                child: c,
              ),
            ),
          ),
        );
      },
      child: child,
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
      Color(0xFF4F46E5),
      Color(0xFF15803D),
      Color(0xFF0369A1),
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

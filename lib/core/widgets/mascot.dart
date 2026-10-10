import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/templates/templates.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// The CallPilot mascot: a little blue bird.
///
/// He is the product's character, not a customer's AI employee (those are
/// [EmployeeAvatar] monograms). He shows up where people already look: the
/// Home hero, onboarding, empty states, errors and wins.
///
/// Personality: an eager, quick little helper who loves good news. Idle is
/// calm (a gentle bob, the odd blink); the big energy is saved for wins.
///
/// Every state is drawn in code – the bird ([BirdPainter]) plus a state
/// overlay ([MascotOverlayPainter]: phone and sound waves, confetti, "z z",
/// thought dots, motion lines) – so it is crisp at any size and costs no
/// APK space. If artwork for a state is added as `assets/mascot/<name>.png`
/// it replaces the drawing (see `assets/mascot/README.md`).
enum MascotState {
  /// Default: calm, breathing, blinking.
  idle(BirdPose.idle),

  /// A call is live: talking beak, a phone and sound waves.
  calling(BirdPose.speaking),

  /// A win (ready-to-buy lead, checklist done): hop + confetti.
  celebrating(BirdPose.success),

  /// Outside calling hours: eyes closed, drifting "z z".
  resting(BirdPose.resting),

  /// Working something out / nothing here yet / errors: thought dots.
  thinking(BirdPose.thinking),

  /// Hello: a wink, a waving wing, a little rock side to side.
  waving(BirdPose.welcome);

  const MascotState(this.pose);

  /// The drawn pose used when no artwork file exists for this state.
  final BirdPose pose;

  /// Optional artwork that replaces the drawing (512×512 transparent PNG).
  String get asset => 'assets/mascot/$name.png';
}

/// Which `assets/mascot/<state>.png` files are bundled. Read once from the
/// asset manifest; until then (and when nothing is bundled) the drawn bird
/// is used.
class MascotAssets {
  MascotAssets._();

  static Set<String>? _available;
  static Future<Set<String>>? _loading;

  /// Test hook: pretend exactly these asset paths exist (null = real
  /// manifest).
  @visibleForTesting
  static Set<String>? debugOverride;

  /// Synchronous answer if known: null while the manifest is loading.
  static bool? has(MascotState s) {
    final set = debugOverride ?? _available;
    return set?.contains(s.asset);
  }

  /// Loads the manifest (once).
  static Future<Set<String>> load([AssetBundle? bundle]) {
    if (debugOverride != null) return Future.value(debugOverride);
    if (_available != null) return Future.value(_available);
    return _loading ??= AssetManifest.loadFromAssetBundle(bundle ?? rootBundle)
        .then((m) {
          return _available = m
              .listAssets()
              .where((a) => a.startsWith('assets/mascot/'))
              .toSet();
        })
        .catchError((Object _) => _available = <String>{});
  }

  @visibleForTesting
  static void reset() {
    _available = null;
    _loading = null;
    debugOverride = null;
  }
}

/// The mascot in a [MascotState], with an optional soft halo behind him.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.state = MascotState.idle,
    this.pose,
    this.size = 120,
    this.halo = true,
    this.haloColor,
    this.animate = true,
    this.semanticLabel,
    this.role,
  });

  final MascotState state;

  /// Overrides the drawn bird's face/body (e.g. [BirdPose.error] for a
  /// worried look on error screens, or the voice-test poses). The state's
  /// overlay still plays.
  final BirdPose? pose;
  final double size;
  final bool halo;
  final Color? haloColor;

  /// Off: a still pose (used where many mascots could be on screen).
  final bool animate;
  final String? semanticLabel;

  /// Optional role badge (legacy; employees now use [EmployeeAvatar]).
  final EmployeeRoleKind? role;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  // One clock drives everything: value × 12 = seconds.
  static const _loop = 12.0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _reduced = false;
  bool? _hasArt;

  bool get _moves => widget.animate && !_reduced;

  void _sync() {
    if (_moves) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveArt();
  }

  void _resolveArt() {
    _hasArt = MascotAssets.has(widget.state);
    if (_hasArt == null) {
      MascotAssets.load().then((_) {
        if (mounted) setState(() => _hasArt = MascotAssets.has(widget.state));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    _sync();
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
    if (old.state != widget.state) _resolveArt();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Whole-body rotation (radians) for the state at [t] seconds.
  static double tilt(MascotState s, double t, bool moving) {
    const deg = math.pi / 180;
    final w = moving ? math.sin(t * 0.9 * math.pi * 2) : 0.0;
    return switch (s) {
      MascotState.waving => 8 * deg * w,
      MascotState.resting => 6 * deg,
      MascotState.thinking => -4 * deg,
      _ => 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final art = _hasArt == true;
    Widget body = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          // A still pose sits mid-breath with both eyes open.
          final t = _moves ? _c.value * _loop : 1.0;
          if (art) {
            // Supplied artwork: only a gentle bob, no overlays.
            final bob = _moves
                ? -s * 0.02 * math.sin(t * 0.5 * 2 * math.pi)
                : 0.0;
            return Transform.translate(
              offset: Offset(0, bob),
              child: Image.asset(
                widget.state.asset,
                width: s,
                height: s,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            );
          }
          return Stack(
            children: [
              Transform.rotate(
                angle: tilt(widget.state, t, _moves),
                alignment: const Alignment(0, 0.85),
                child: CustomPaint(
                  size: Size.square(s),
                  painter: BirdPainter(
                    state: widget.pose ?? widget.state.pose,
                    t: t,
                    moving: _moves,
                    extras: false,
                  ),
                ),
              ),
              CustomPaint(
                size: Size.square(s),
                painter: MascotOverlayPainter(
                  state: widget.state,
                  t: t,
                  moving: _moves,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (widget.halo) {
      body = Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: s * 0.86,
            height: s * 0.86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.haloColor ?? AppColors.mascotHalo,
            ),
          ),
          body,
        ],
      );
    }

    final role = widget.role;
    if (role != null && s >= 72) {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            right: s * 0.04,
            bottom: s * 0.06,
            child: RoleBadge(role: role, size: (s * 0.24).clamp(26, 52)),
          ),
        ],
      );
    }

    return Semantics(
      label: widget.semanticLabel ?? 'CallPilot bird',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(width: s, height: s, child: body),
      ),
    );
  }
}

/// The pieces a state's overlay draws.
enum MascotOverlayPart {
  handset,
  soundWaves,
  confetti,
  sleepZs,
  thoughtDots,
  motionLines,
}

/// Draws a [MascotState]'s overlay on top of the bird, in the bird's flat
/// rounded style: royal blue, light blue, beak pink and the marigold accent.
///
/// Shares [BirdPainter]'s coordinate space (the 1254 px character sheet),
/// so positions line up with his head and wings at any size.
class MascotOverlayPainter extends CustomPainter {
  MascotOverlayPainter({
    required this.state,
    required this.t,
    this.moving = true,
  });

  final MascotState state;

  /// Seconds on the mascot clock.
  final double t;

  /// False under reduced motion: a single, meaningful still frame.
  final bool moving;

  static const royal = Color(0xFF1F5BFF);
  static const light = BirdPainter.light;
  static const pink = BirdPainter.pink;
  static const navy = BirdPainter.navy;
  static const marigold = Color(0xFFF5A524);

  /// What [state] draws. Idle is deliberately bare.
  static List<MascotOverlayPart> partsFor(MascotState s) => switch (s) {
    MascotState.idle => const [],
    MascotState.calling => const [
      MascotOverlayPart.handset,
      MascotOverlayPart.soundWaves,
    ],
    MascotState.celebrating => const [MascotOverlayPart.confetti],
    MascotState.resting => const [MascotOverlayPart.sleepZs],
    MascotState.thinking => const [MascotOverlayPart.thoughtDots],
    MascotState.waving => const [MascotOverlayPart.motionLines],
  };

  static const _tau = math.pi * 2;

  /// Loop phase 0..1 with period [seconds]; a fixed, readable phase when
  /// still.
  double _phase(double seconds, [double offset = 0, double still = 0.45]) =>
      moving ? ((t / seconds) + offset) % 1.0 : (still + offset) % 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final parts = partsFor(state);
    if (parts.isEmpty) return;
    final k = size.shortestSide * 0.9 / 1117;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-648, -630);
    for (final p in parts) {
      switch (p) {
        case MascotOverlayPart.handset:
          _handset(canvas);
        case MascotOverlayPart.soundWaves:
          _soundWaves(canvas);
        case MascotOverlayPart.confetti:
          _confetti(canvas);
        case MascotOverlayPart.sleepZs:
          _zs(canvas);
        case MascotOverlayPart.thoughtDots:
          _thoughtDots(canvas);
        case MascotOverlayPart.motionLines:
          _motionLines(canvas);
      }
    }
    canvas.restore();
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// A small rounded navy handset held by his right cheek.
  void _handset(Canvas c) {
    c.save();
    c.translate(990, 470);
    c.rotate(-0.55);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 86, height: 250),
      const Radius.circular(43),
    );
    c.drawRRect(body, Paint()..color = navy);
    // Ear and mouth pieces.
    for (final y in [-92.0, 92.0]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(-26, y), width: 92, height: 70),
          const Radius.circular(30),
        ),
        Paint()..color = navy,
      );
    }
    // A highlight so it reads as an object, not a hole.
    c.drawLine(
      const Offset(14, -60),
      const Offset(14, 40),
      _stroke(Colors.white.withValues(alpha: 0.35), 12),
    );
    c.restore();
  }

  /// Two or three arcs rippling out from the phone.
  void _soundWaves(Canvas c) {
    const centre = Offset(1060, 330);
    for (var i = 0; i < 3; i++) {
      final p = _phase(1.4, i / 3);
      final r = 50 + 110 * p;
      final alpha = moving ? (1 - p) : 0.85 - i * 0.2;
      c.drawArc(
        Rect.fromCircle(center: centre, radius: r),
        -1.5,
        1.25,
        false,
        _stroke(royal.withValues(alpha: alpha.clamp(0.0, 1.0)), 20),
      );
    }
  }

  /// Bits of marigold, blue and pink bursting out and falling, every 2.4 s.
  void _confetti(Canvas c) {
    final p = _phase(2.4, 0, 0.35);
    final out = Curves.easeOutCubic.transform(p);
    const colors = [marigold, royal, pink, light];
    const centre = Offset(650, 520);
    for (var i = 0; i < 18; i++) {
      final angle = -math.pi / 2 + (i / 18 - 0.5) * math.pi * 1.6;
      final speed = 0.65 + (i * 37 % 40) / 100;
      final dist = 560 * speed * out;
      final gravity = 260 * p * p;
      final pos =
          centre +
          Offset(dist * math.cos(angle), dist * math.sin(angle) + gravity);
      final alpha = moving ? (1 - p * p).clamp(0.0, 1.0) : 1.0;
      c.save();
      c.translate(pos.dx, pos.dy);
      c.rotate((i % 5 - 2) * 2.2 * p + i);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: alpha);
      if (i % 3 == 0) {
        c.drawCircle(Offset.zero, 18, paint);
      } else {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 46, height: 22),
            const Radius.circular(10),
          ),
          paint,
        );
      }
      c.restore();
    }
  }

  /// Light-blue "z z" drifting up and fading.
  void _zs(Canvas c) {
    for (var i = 0; i < 2; i++) {
      final p = _phase(3.2, i * 0.5, 0.3);
      final size = 64.0 + i * 26;
      final x = 960 + 70 * i + 30 * math.sin(p * _tau);
      final y = 400 - i * 130 - 150 * p;
      final alpha = moving ? math.sin(p * math.pi) : 1.0;
      _drawZ(c, Offset(x, y), size, light.withValues(alpha: alpha));
    }
  }

  void _drawZ(Canvas c, Offset o, double s, Color color) {
    final path = Path()
      ..moveTo(o.dx - s / 2, o.dy - s / 2)
      ..lineTo(o.dx + s / 2, o.dy - s / 2)
      ..lineTo(o.dx - s / 2, o.dy + s / 2)
      ..lineTo(o.dx + s / 2, o.dy + s / 2);
    c.drawPath(path, _stroke(color, s * 0.2));
  }

  /// Three dots rising from his head in a thought trail.
  void _thoughtDots(Canvas c) {
    for (var i = 0; i < 3; i++) {
      final p = _phase(1.8, -i * 0.18, 1.0);
      final lift = moving ? 14 * math.sin(p * _tau) : 0.0;
      final a = moving ? 0.45 + 0.55 * (0.5 + 0.5 * math.sin(p * _tau)) : 1.0;
      c.drawCircle(
        Offset(940 + i * 72, 250 - i * 60 - lift),
        20.0 + i * 9,
        Paint()..color = royal.withValues(alpha: a),
      );
    }
  }

  /// Motion lines by the raised (right) wing.
  void _motionLines(Canvas c) {
    final pulse = moving ? 0.6 + 0.4 * math.sin(t * 1.8 * _tau) : 1.0;
    final paint = _stroke(marigold.withValues(alpha: pulse), 26);
    c.save();
    c.translate(1150, 600);
    c.scale(0.9 + 0.1 * pulse);
    c.translate(-1150, -600);
    c.drawLine(const Offset(1150, 470), const Offset(1210, 430), paint);
    c.drawLine(const Offset(1180, 580), const Offset(1250, 570), paint);
    c.drawLine(const Offset(1150, 690), const Offset(1210, 720), paint);
    c.restore();
  }

  @override
  bool shouldRepaint(MascotOverlayPainter o) =>
      o.t != t || o.state != state || o.moving != moving;
}

/// The drawn bird's face and body language. [MascotState] picks one; a
/// few screens (voice test, errors) ask for a specific pose directly.
enum BirdPose {
  welcome,
  speaking,
  listening,
  thinking,
  calling,
  success,
  hotLead,
  whatsapp,
  error,
  idle,
  resting,
}

/// Paints the bird in any [BirdPose] at time [t] (seconds).
///
/// Coordinates follow the original 1254 px character sheet, so tweaks can
/// be read straight off the artwork.
class BirdPainter extends CustomPainter {
  BirdPainter({
    required this.state,
    required this.t,
    this.moving = true,
    this.extras = true,
  });

  final BirdPose state;

  /// Paint the pose's own effects (thinking dots, call waves…). The
  /// [Mascot] widget turns these off and draws its overlay set instead.
  final bool extras;
  final double t;
  final bool moving;

  // Palette from the character sheet.
  static const blue = Color(0xFF0562FD);
  static const deep = Color(0xFF003FE3);
  static const light = Color(0xFF80BDFC);
  static const lightShade = Color(0xFF5E9EFA);
  static const pink = Color(0xFFFD8BB2);
  static const hotPink = Color(0xFFFC2E7B);
  static const mouth = Color(0xFFB8104F);
  static const navy = Color(0xFF0E173A);

  static const _tau = math.pi * 2;

  double _wave(double hz, [double phase = 0]) =>
      math.sin((t * hz + phase) * _tau);

  /// 1 → 0 → 1 over a quick blink every ~3.6 s.
  double get _blink {
    if (!moving) return 1;
    final p = (t % 3.6) / 3.6;
    const w = 0.04;
    if (p > w) return 1;
    return (1 - math.sin(p / w * math.pi)).clamp(0.08, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide * 0.9 / 1117;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-648, -630);

    // ---- Whole-body motion per state.
    var hop = 0.0, sway = 0.0, squash = 1.0;
    final breathe = 1 + 0.018 * _wave(0.42);
    switch (state) {
      case BirdPose.success:
      case BirdPose.hotLead:
        final h = _wave(1.4).abs();
        hop = -60 * h;
        squash = 1 - 0.06 * (1 - h) * (1 - h);
      case BirdPose.speaking:
        hop = -8 * _wave(2.2).abs();
      case BirdPose.listening:
        sway = 0.07 * _wave(0.35);
      case BirdPose.thinking:
        sway = -0.05 + 0.025 * _wave(0.3);
      case BirdPose.calling:
        hop = -10 * _wave(1.1).abs();
      case BirdPose.error:
        sway = 0.035 * _wave(0.25);
        squash = 0.97;
      case BirdPose.welcome:
      case BirdPose.whatsapp:
        hop = -6 * _wave(0.5).abs();
      case BirdPose.idle:
        hop = -7 * (0.5 + 0.5 * _wave(0.4));
      case BirdPose.resting:
        squash = 0.985;
    }
    if (!moving) {
      hop = 0;
      sway = state == BirdPose.thinking ? -0.05 : 0;
      squash = state == BirdPose.error
          ? 0.97
          : state == BirdPose.resting
          ? 0.985
          : 1;
    }

    // Soft ground shadow (shrinks as he hops up).
    final lift = (-hop / 60).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(690, 1165),
        width: 520 * (1 - 0.3 * lift),
        height: 46 * (1 - 0.3 * lift),
      ),
      Paint()..color = navy.withValues(alpha: 0.08 * (1 - 0.5 * lift)),
    );

    canvas.save();
    canvas.translate(0, hop);
    // Squash/stretch and sway pivot on his feet.
    canvas.translate(650, 1100);
    canvas.rotate(sway);
    canvas.scale(2 - squash * breathe, squash * breathe);
    canvas.translate(-650, -1100);

    _wings(canvas, back: true);
    _body(canvas);
    _wings(canvas, back: false);
    _feet(canvas);
    _face(canvas);
    canvas.restore();

    _extras(canvas, hop);
    canvas.restore();
  }

  // ------------------------------------------------------------- parts

  void _oval(
    Canvas c,
    Offset center,
    double rx,
    double ry,
    double deg,
    Color color,
  ) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(deg * math.pi / 180);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()..color = color,
    );
    c.restore();
  }

  /// Wing angle (radians) for the left/right wing in the current state.
  double _wingAngle(bool left) {
    if (!moving) return 0;
    switch (state) {
      case BirdPose.welcome:
        // Right wing waves hello; left wing rests.
        return left ? 0.04 * _wave(0.5) : -0.32 * (0.5 + 0.5 * _wave(1.5));
      case BirdPose.success:
      case BirdPose.hotLead:
        final f = -0.38 * (0.5 + 0.5 * _wave(2.8));
        return left ? -f : f;
      case BirdPose.speaking:
        return (left ? 1 : -1) * 0.08 * _wave(1.2);
      case BirdPose.error:
        return (left ? -1 : 1) * 0.12;
      default:
        return (left ? 1 : -1) * 0.03 * _wave(0.42);
    }
  }

  void _wings(Canvas c, {required bool back}) {
    for (final left in [true, false]) {
      final pivot = left ? const Offset(450, 820) : const Offset(880, 740);
      c.save();
      c.translate(pivot.dx, pivot.dy);
      c.rotate(_wingAngle(left));
      c.translate(-pivot.dx, -pivot.dy);
      if (left) {
        if (back) {
          _oval(c, const Offset(232, 790), 112, 66, 22, deep);
          _oval(c, const Offset(212, 892), 118, 62, 8, deep);
          _oval(c, const Offset(292, 985), 110, 58, -4, deep);
        } else {
          _oval(c, const Offset(360, 885), 138, 104, -38, lightShade);
          _oval(c, const Offset(350, 868), 128, 92, -38, light);
        }
      } else {
        if (back) {
          _oval(c, const Offset(1062, 628), 112, 58, -58, deep);
          _oval(c, const Offset(1098, 752), 104, 54, -30, deep);
          _oval(c, const Offset(1050, 862), 96, 50, -8, deep);
        } else {
          _oval(c, const Offset(975, 775), 128, 96, -52, lightShade);
          _oval(c, const Offset(985, 760), 118, 86, -52, light);
        }
      }
      c.restore();
    }
  }

  void _body(Canvas c) {
    final paint = Paint()..color = blue;
    // Round body.
    c.drawOval(
      Rect.fromCenter(center: const Offset(622, 690), width: 760, height: 820),
      paint,
    );
    // Crest: one long swoosh and a smaller tuft.
    final crest = Path()
      ..moveTo(430, 330)
      ..cubicTo(560, 250, 700, 200, 760, 110)
      ..cubicTo(790, 65, 830, 70, 826, 125)
      ..cubicTo(820, 190, 790, 240, 760, 262)
      ..cubicTo(800, 230, 850, 190, 872, 192)
      ..cubicTo(905, 196, 900, 250, 870, 300)
      ..lineTo(820, 420)
      ..lineTo(470, 420)
      ..close();
    c.drawPath(crest, paint);
    // Belly.
    _oval(c, const Offset(688, 935), 182, 150, -14, light);
  }

  void _feet(Canvas c) {
    _oval(c, const Offset(510, 1110), 100, 70, -4, pink);
    _oval(c, const Offset(880, 1020), 100, 84, -30, pink);
    final toe = Paint()
      ..color = hotPink
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(508, 1084), const Offset(516, 1158), toe);
    c.drawLine(const Offset(898, 990), const Offset(872, 1076), toe);
  }

  void _face(Canvas c) {
    // Brow / cheek spots.
    _oval(c, const Offset(478, 455), 62, 40, -25, light);
    _oval(c, const Offset(790, 378), 56, 33, -5, light);

    // Where the pupils look.
    var look = Offset.zero;
    switch (state) {
      case BirdPose.thinking:
        look = const Offset(-14, -18);
      case BirdPose.error:
        look = const Offset(-6, 14);
      case BirdPose.listening:
        look = Offset(10 * _wave(0.2), 0);
      default:
        break;
    }

    if (state == BirdPose.resting) {
      // Sleepy: both eyes closed as soft downward arcs, beak shut.
      _sleepEye(c, const Offset(505, 610), 70);
      _sleepEye(c, const Offset(835, 545), 78);
      _beak(c);
      return;
    }

    final happy = state == BirdPose.success || state == BirdPose.hotLead;
    final wink = state == BirdPose.welcome;
    final blink = _blink;

    // Left eye: wink (welcome), happy arc (success) or open.
    if (wink || happy) {
      _arcEye(c, const Offset(505, 625), 74);
    } else {
      _openEye(c, const Offset(505, 600), 74, look, blink);
    }
    // Right eye.
    if (happy) {
      _arcEye(c, const Offset(835, 555), 80);
    } else {
      _openEye(c, const Offset(835, 535), 86, look, blink);
    }

    if (state == BirdPose.error) {
      // Worried lids.
      final lid = Paint()..color = blue;
      c.drawRect(const Rect.fromLTRB(425, 515, 585, 575), lid);
      c.drawRect(const Rect.fromLTRB(745, 445, 925, 505), lid);
    }

    _beak(c);
  }

  void _openEye(Canvas c, Offset o, double r, Offset look, double open) {
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(1, open);
    c.drawCircle(Offset.zero, r, Paint()..color = Colors.white);
    final pupil = Offset(-22, 10) + look;
    c.drawCircle(pupil, r * 0.77, Paint()..color = navy);
    c.drawCircle(
      pupil + Offset(-r * 0.32, -r * 0.42),
      r * 0.24,
      Paint()..color = Colors.white,
    );
    c.restore();
  }

  void _sleepEye(Canvas c, Offset o, double r) {
    c.drawArc(
      Rect.fromCircle(center: o, radius: r * 0.8),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round,
    );
  }

  void _arcEye(Canvas c, Offset o, double r) {
    c.drawArc(
      Rect.fromCircle(center: o, radius: r * 0.95),
      math.pi * 1.12,
      math.pi * 0.76,
      false,
      Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..strokeCap = StrokeCap.round,
    );
  }

  /// How far the beak is open, 0..1.
  double get _open {
    if (!moving) {
      return switch (state) {
        BirdPose.error || BirdPose.thinking || BirdPose.resting => 0.0,
        BirdPose.idle => 0.45,
        _ => 0.7,
      };
    }
    return switch (state) {
      BirdPose.speaking => (0.5 + 0.5 * _wave(4.6)).clamp(0.1, 1.0),
      BirdPose.calling => 0.35 + 0.25 * _wave(2.2),
      BirdPose.success || BirdPose.hotLead => 1.0,
      BirdPose.welcome || BirdPose.whatsapp => 0.75,
      BirdPose.listening => 0.15,
      BirdPose.thinking || BirdPose.error || BirdPose.resting => 0.0,
      BirdPose.idle => 0.45,
    };
  }

  void _beak(Canvas c) {
    final o = _open;
    // Upper beak: a rounded triangle pointing down-right.
    final beak = Path()
      ..moveTo(600, 640)
      ..quadraticBezierTo(580, 660, 600, 680)
      ..lineTo(690, 742 + 14 * o)
      ..quadraticBezierTo(712, 756 + 14 * o, 722, 732 + 14 * o)
      ..lineTo(774, 618)
      ..quadraticBezierTo(782, 590, 752, 594)
      ..close();
    c.drawPath(beak, Paint()..color = pink);
    if (o > 0.04) {
      // Open mouth with a tongue.
      final m = Path()
        ..moveTo(622, 662)
        ..lineTo(740, 630)
        ..lineTo(706, 662 + 66 * o)
        ..quadraticBezierTo(690, 680 + 66 * o, 676, 664 + 60 * o)
        ..close();
      c.drawPath(m, Paint()..color = mouth);
      c.save();
      c.clipPath(m);
      _oval(c, Offset(700, 690 + 50 * o), 46, 30 * o + 6, -10, hotPink);
      c.restore();
    } else {
      c.drawLine(
        const Offset(625, 665),
        const Offset(742, 632),
        Paint()
          ..color = mouth
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Effects around him: excitement lines, thinking dots, call waves,
  /// a sweat drop, a chat bubble.
  void _extras(Canvas c, double hop) {
    if (!extras) return;
    final pulse = moving ? 0.5 + 0.5 * _wave(1.6) : 1.0;
    switch (state) {
      case BirdPose.welcome:
      case BirdPose.success:
      case BirdPose.hotLead:
        final color = state == BirdPose.hotLead ? hotPink : blue;
        final p = Paint()
          ..color = color.withValues(alpha: 0.55 + 0.45 * pulse)
          ..strokeWidth = 30
          ..strokeCap = StrokeCap.round;
        final grow = 0.85 + 0.15 * pulse;
        c.save();
        c.translate(1060, 380 + hop * 0.5);
        c.scale(grow);
        c.translate(-1060, -380);
        c.drawLine(const Offset(1040, 270), const Offset(1002, 350), p);
        c.drawLine(const Offset(1110, 358), const Offset(1046, 402), p);
        c.drawLine(const Offset(1112, 458), const Offset(1062, 464), p);
        c.restore();
      case BirdPose.thinking:
        for (var i = 0; i < 3; i++) {
          final a = moving
              ? (0.5 + 0.5 * math.sin((t * 1.2 - i * 0.22) * _tau))
              : 1.0;
          c.drawCircle(
            Offset(960 + i * 70, 250 - i * 24),
            24 + i * 4,
            Paint()..color = deep.withValues(alpha: 0.25 + 0.6 * a),
          );
        }
      case BirdPose.calling:
        for (var i = 0; i < 2; i++) {
          final p = moving ? ((t * 0.9 + i * 0.5) % 1.0) : 0.5;
          c.drawArc(
            Rect.fromCircle(
              center: const Offset(940, 470),
              radius: 40 + 120 * p,
            ),
            -0.7,
            1.4,
            false,
            Paint()
              ..color = blue.withValues(alpha: 0.7 * (1 - p))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 22
              ..strokeCap = StrokeCap.round,
          );
        }
      case BirdPose.error:
        final y = moving ? 40 * ((t * 0.5) % 1.0) : 0.0;
        final drop = Path()
          ..moveTo(1000, 330 + y)
          ..quadraticBezierTo(1050, 410 + y, 1000, 440 + y)
          ..quadraticBezierTo(950, 410 + y, 1000, 330 + y)
          ..close();
        c.drawPath(drop, Paint()..color = light);
      case BirdPose.whatsapp:
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(930, 210 + hop * 0.5, 230, 150),
          const Radius.circular(60),
        );
        c.drawRRect(r, Paint()..color = const Color(0xFF25D366));
        for (var i = 0; i < 3; i++) {
          final a = moving
              ? (0.5 + 0.5 * math.sin((t * 1.4 - i * 0.2) * _tau))
              : 1.0;
          c.drawCircle(
            Offset(995 + i * 50, 285 + hop * 0.5),
            15,
            Paint()..color = Colors.white.withValues(alpha: 0.5 + 0.5 * a),
          );
        }
      case BirdPose.listening:
      case BirdPose.speaking:
      case BirdPose.idle:
      case BirdPose.resting:
        break;
    }
  }

  @override
  bool shouldRepaint(BirdPainter o) =>
      o.t != t || o.state != state || o.moving != moving || o.extras != extras;
}

/// Accessory badge for a role (used by employee avatars).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.size = 34});
  final EmployeeRoleKind role;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surface,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.brandSoft, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Icon(AppIcons.role(role), size: size * 0.5, color: AppColors.brand),
  );
}

/// Circular crop of the mascot for list rows and chips.
class MascotAvatar extends StatelessWidget {
  const MascotAvatar({
    super.key,
    this.size = 44,
    this.state = MascotState.waving,
    this.pose,
    this.ring,
  });
  final double size;
  final MascotState state;
  final BirdPose? pose;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.mascotHalo,
        border: ring == null ? null : Border.all(color: ring!, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        maxWidth: size * 1.3,
        maxHeight: size * 1.3,
        alignment: const Alignment(0, -0.2),
        child: Mascot(
          state: state,
          pose: pose,
          size: size * 1.3,
          halo: false,
          animate: false,
        ),
      ),
    );
  }
}

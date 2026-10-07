import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/templates/templates.dart';
import '../theme/app_colors.dart';

/// The CallPilot AI-workforce mascot.
///
/// It represents CallPilot's AI employees in general – NOT a specific named
/// employee. Each employee adapts it through a role badge/accessory
/// ([EmployeeRoleKind]: sales 💼, appointments 📅, support 💬, admissions 📚…),
/// so the visual identity stays consistent across every industry.
///
/// Asset files live in `assets/mascot/<state>.png`. Swap files to restyle –
/// layouts never change.
enum MascotState {
  welcome('welcome'),
  speaking('speaking'),
  listening('listening'),
  thinking('thinking'),
  calling('calling'),
  success('success'),
  hotLead('hot_lead'),
  whatsapp('whatsapp'),
  error('error');

  const MascotState(this.file);
  final String file;
}

class MascotConfig {
  const MascotConfig._();
  static String basePath = 'assets/mascot';
  static String path(MascotState s) => '$basePath/${s.file}.png';
}

/// Reusable mascot with halo + optional subtle, purposeful motion.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.state = MascotState.welcome,
    this.size = 120,
    this.halo = true,
    this.haloColor,
    this.animate = true,
    this.semanticLabel,
    this.role,
  });

  final MascotState state;
  final double size;
  final bool halo;
  final Color? haloColor;
  final bool animate;
  final String? semanticLabel;

  /// Optional role badge (accessory) for the employee being shown.
  final EmployeeRoleKind? role;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  bool get _moves =>
      widget.animate &&
      const {
        MascotState.listening,
        MascotState.speaking,
        MascotState.thinking,
        MascotState.calling,
        MascotState.success,
      }.contains(widget.state);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _duration);
    _sync();
  }

  Duration get _duration => switch (widget.state) {
    MascotState.speaking => const Duration(milliseconds: 700),
    MascotState.success => const Duration(milliseconds: 900),
    _ => const Duration(milliseconds: 2400),
  };

  void _sync() {
    _c.duration = _duration;
    if (_moves) {
      if (widget.state == MascotState.success) {
        _c.forward(from: 0);
      } else {
        _c.repeat(reverse: true);
      }
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant Mascot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.animate != widget.animate) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final img = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(a),
          child: child,
        ),
      ),
      child: Image.asset(
        MascotConfig.path(widget.state),
        key: ValueKey(widget.state),
        width: s,
        height: s,
        fit: BoxFit.contain,
        cacheWidth: (s * MediaQuery.devicePixelRatioOf(context)).round().clamp(
          64,
          512,
        ),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _MascotFallback(size: s),
      ),
    );

    Widget body = AnimatedBuilder(
      animation: _c,
      child: img,
      builder: (context, child) {
        final t = _c.value;
        var dy = 0.0, scale = 1.0, rot = 0.0;
        switch (widget.state) {
          case MascotState.listening:
            dy = -2 * t;
            rot = 0.012 * (t - 0.5);
          case MascotState.speaking:
            scale = 1 + 0.018 * t;
          case MascotState.thinking:
            rot = 0.02 * math.sin(t * math.pi);
            dy = -1.5 * t;
          case MascotState.calling:
            dy = -3 * t;
          case MascotState.success:
            scale = 1 + 0.08 * math.sin(t * math.pi);
          default:
        }
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: rot,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );

    if (widget.halo) {
      body = Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: s * 0.92,
                height: s * 0.92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.haloColor ?? AppColors.mascotHalo,
                ),
              ),
            ),
          ),
          body,
        ],
      );
    }

    if (widget.role != null && s >= 72) {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            right: s * 0.04,
            bottom: s * 0.06,
            child: RoleBadge(
              role: widget.role!,
              size: (s * 0.24).clamp(26, 52),
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: widget.semanticLabel ?? 'AI employee illustration',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(width: s, height: s, child: body),
      ),
    );
  }
}

/// Accessory badge that adapts the shared mascot to an employee role.
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
      color: Colors.white,
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
    child: Text(role.badge, style: TextStyle(fontSize: size * 0.5, height: 1)),
  );
}

/// Circular avatar crop of the mascot for list rows / chips.
class MascotAvatar extends StatelessWidget {
  const MascotAvatar({
    super.key,
    this.size = 44,
    this.state = MascotState.welcome,
    this.ring,
  });
  final double size;
  final MascotState state;
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
        maxWidth: size * 1.35,
        maxHeight: size * 1.35,
        alignment: const Alignment(0, -0.35),
        child: Image.asset(
          MascotConfig.path(state),
          width: size * 1.35,
          height: size * 1.35,
          fit: BoxFit.cover,
          cacheWidth: (size * 1.35 * MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(48, 512),
          errorBuilder: (_, __, ___) => _MascotFallback(size: size),
        ),
      ),
    );
  }
}

/// Vector fallback if an asset is missing – same friendly silhouette.
class _MascotFallback extends StatelessWidget {
  const _MascotFallback({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MascotPainter());
}

class _MascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()..isAntiAlias = true;
    // body
    p.color = const Color(0xFFE8705A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .2, w * .62, w * .6, w * .4),
        Radius.circular(w * .2),
      ),
      p,
    );
    // face
    p.color = const Color(0xFFC98B67);
    canvas.drawCircle(Offset(w * .5, w * .42), w * .22, p);
    // hair
    p.color = const Color(0xFF1E1A1D);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * .5, w * .4), radius: w * .24),
      math.pi,
      math.pi,
      true,
      p,
    );
    // eyes
    canvas.drawCircle(Offset(w * .42, w * .44), w * .025, p);
    canvas.drawCircle(Offset(w * .58, w * .44), w * .025, p);
    // headset
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .035
      ..color = const Color(0xFF3B3F4A);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * .5, w * .42), radius: w * .27),
      math.pi * 1.05,
      math.pi * .9,
      false,
      p,
    );
    // smile
    p
      ..strokeWidth = w * .018
      ..color = const Color(0xFF7A3B2E);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * .5, w * .5), radius: w * .06),
      .3,
      math.pi - .6,
      false,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

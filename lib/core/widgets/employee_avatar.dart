import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../providers.dart';
import '../theme/app_colors.dart';
import 'mascot.dart' show RoleBadge;

/// What the AI employee is doing right now, shown as rings around its
/// avatar.
enum EmployeeActivity { idle, calling, listening, speaking, thinking }

/// The customer's AI employee: a monogram of the name the owner chose plus
/// a role badge.
///
/// Deliberately NOT the CallPilot mascot. The mascot is our brand; the
/// employee is the customer's, and its name, gender and voice are theirs to
/// choose. A monogram can never contradict any of them.
class EmployeeAvatar extends StatefulWidget {
  const EmployeeAvatar({
    super.key,
    required this.name,
    this.role,
    this.size = 56,
    this.activity = EmployeeActivity.idle,
    this.onDark = false,
    this.semanticLabel,
  });

  final String name;
  final EmployeeRoleKind? role;
  final double size;
  final EmployeeActivity activity;

  /// White disc for use on a coloured card (e.g. the home hero).
  final bool onDark;
  final String? semanticLabel;

  /// "Riya" → "R", "Kabir Singh" → "KS". Grapheme-safe, so Devanagari and
  /// Bengali names keep their full first letter.
  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  State<EmployeeAvatar> createState() => _EmployeeAvatarState();
}

class _EmployeeAvatarState extends State<EmployeeAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _period(widget.activity),
  );
  bool _reduced = false;

  static Duration _period(EmployeeActivity a) => switch (a) {
    EmployeeActivity.speaking => const Duration(milliseconds: 1100),
    EmployeeActivity.thinking => const Duration(milliseconds: 1400),
    _ => const Duration(milliseconds: 2200),
  };

  bool get _moves => widget.activity != EmployeeActivity.idle && !_reduced;

  void _sync() {
    _c.duration = _period(widget.activity);
    if (_moves) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    _sync();
  }

  @override
  void didUpdateWidget(EmployeeAvatar old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _ringColor => switch (widget.activity) {
    EmployeeActivity.speaking => AppColors.brand,
    EmployeeActivity.thinking => AppColors.inkFaint,
    _ => AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final letters = EmployeeAvatar.initials(widget.name);
    final fill = widget.onDark ? Colors.white : AppColors.brandFill;
    final ink = widget.onDark ? AppColors.brandFill : Colors.white;
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fill, Color.lerp(fill, Colors.black, 0.16)!],
        ),
      ),
      child: letters.isEmpty
          ? Icon(Icons.support_agent_rounded, size: size * 0.48, color: ink)
          : Text(
              letters,
              maxLines: 1,
              style: TextStyle(
                color: ink,
                fontSize: size * (letters.characters.length > 1 ? 0.36 : 0.44),
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
    );
    final role = widget.role;
    return Semantics(
      label: widget.semanticLabel ?? widget.name,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Rings paint outside the avatar's box, so a state change
              // never shifts the layout around it.
              if (widget.activity != EmployeeActivity.idle)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, _) => CustomPaint(
                        painter: _ActivityPainter(
                          t: _moves ? _c.value : 0.35,
                          activity: widget.activity,
                          color: _ringColor,
                          animated: _moves,
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  // Speaking: the disc "talks" with a soft pulse.
                  final talk =
                      widget.activity == EmployeeActivity.speaking && _moves
                      ? 1 + 0.035 * math.sin(_c.value * math.pi * 2)
                      : 1.0;
                  return Transform.scale(scale: talk, child: child);
                },
                child: disc,
              ),
              if (role != null && size >= 40)
                Positioned(
                  right: -size * 0.04,
                  bottom: -size * 0.02,
                  child: RoleBadge(
                    role: role,
                    size: (size * 0.34).clamp(18.0, 44.0),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityPainter extends CustomPainter {
  _ActivityPainter({
    required this.t,
    required this.activity,
    required this.color,
    required this.animated,
  });
  final double t;
  final EmployeeActivity activity;
  final Color color;
  final bool animated;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (activity == EmployeeActivity.thinking) {
      // A short arc orbiting the avatar: "working on it".
      final rect = Rect.fromCircle(center: c, radius: r + 6);
      canvas.drawArc(
        rect,
        t * math.pi * 2,
        math.pi * 0.6,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    if (!animated) {
      canvas.drawCircle(
        c,
        r + 5,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    // Calling / listening / speaking: rings ripple outwards.
    const rings = 2;
    for (var i = 0; i < rings; i++) {
      final p = (t + i / rings) % 1.0;
      final radius = r + 3 + r * 0.42 * Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.35 * (1 - p))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_ActivityPainter o) =>
      o.t != t ||
      o.activity != activity ||
      o.color != color ||
      o.animated != animated;
}

/// [EmployeeAvatar] for the business's current AI employee (or [agent]).
/// Renaming the employee or changing its role updates it everywhere.
class AgentAvatar extends ConsumerWidget {
  const AgentAvatar({
    super.key,
    this.agent,
    this.size = 56,
    this.activity = EmployeeActivity.idle,
    this.onDark = false,
    this.showRole = true,
  });

  final Agent? agent;
  final double size;
  final EmployeeActivity activity;
  final bool onDark;
  final bool showRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final a = agent ?? ref.watch(agentProvider).value;
    final role = a == null
        ? null
        : EmployeeRoleKind.parse(
            a.roleKind == 'general'
                ? EmployeeRoleKind.fromRole(a.role).name
                : a.roleKind,
          );
    return EmployeeAvatar(
      name: a?.name ?? '',
      role: showRole ? role : null,
      size: size,
      activity: activity,
      onDark: onDark,
      semanticLabel: a == null
          ? s.yourAiEmployee
          : '${a.name}, ${s.data(a.role)}',
    );
  }
}

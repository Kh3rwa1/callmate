import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/templates/templates.dart';
import '../config/brand.dart';
import '../providers.dart';
import '../theme/app_colors.dart';
import 'mascot.dart';

/// CallPilot logo mark (uses the launcher icon asset).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.26),
    child: Image.asset(
      'assets/icon/app_icon.png',
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: Brand.appName,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: AppColors.brandFill,
        child: Icon(Icons.call_rounded, color: Colors.white, size: size * 0.55),
      ),
    ),
  );
}

/// "CallPilot" wordmark – always exact capitalization from [Brand.appName].
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.size = 18,
    this.showMark = true,
    this.color,
  });
  final double size;
  final bool showMark;

  /// Defaults to [AppColors.ink].
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showMark) ...[
        BrandMark(size: size * 1.9),
        SizedBox(width: size * 0.55),
      ],
      Text(
        Brand.appName,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: color ?? AppColors.ink,
          letterSpacing: -0.3,
        ),
      ),
    ],
  );
}

/// Mascot bound to the current AI employee (role → badge). Changing
/// agent.role automatically changes the accessory everywhere.
class EmployeeMascot extends ConsumerWidget {
  const EmployeeMascot({
    super.key,
    this.state = MascotState.welcome,
    this.size = 120,
    this.halo = true,
    this.animate = true,
    this.agent,
  });
  final MascotState state;
  final double size;
  final bool halo;
  final bool animate;
  final Agent? agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = agent ?? ref.watch(agentProvider).value;
    final role = a == null
        ? null
        : EmployeeRoleKind.parse(
            a.roleKind == 'general'
                ? EmployeeRoleKind.fromRole(a.role).name
                : a.roleKind,
          );
    return Mascot(
      state: state,
      size: size,
      halo: halo,
      animate: animate,
      role: role,
      semanticLabel: a == null ? 'AI employee' : '${a.name}, ${a.role}',
    );
  }
}

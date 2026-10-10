import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'mascot.dart';

/// Shimmering skeleton block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});
  final double height;
  final double? width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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
    final box = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    if (AppMotion.reduced(context)) return box;
    // A soft highlight sweeps left → right across the placeholder.
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = -1.0 + 3.0 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x, 0),
            colors: [
              AppColors.surfaceMuted,
              AppColors.skeletonHighlight,
              AppColors.surfaceMuted,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(r);
        },
        child: child,
      ),
      child: box,
    );
  }
}

/// Placeholder for one list row (avatar, two lines, trailing pill).
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(
      children: [
        Skeleton(height: 42, width: 42, radius: 21),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: 0.6,
                child: Skeleton(height: 15),
              ),
              SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: 0.85,
                child: Skeleton(height: 12),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Skeleton(height: 24, width: 64, radius: 12),
      ],
    ),
  );
}

/// Placeholder shaped like the grouped list it stands in for, so nothing
/// jumps when the real rows arrive.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.all(AppSpace.page),
  });
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.s.loading,
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        CardGroup(
          indent: 70,
          children: [for (var i = 0; i < count; i++) const SkeletonRow()],
        ),
      ],
    ),
  );
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3, this.height});
  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.s.loading,
    child: AppCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Skeleton(height: 44, width: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(child: Skeleton(height: 18)),
                SizedBox(width: 60),
              ],
            ),
            for (var i = 0; i < lines; i++) ...[
              const SizedBox(height: 12),
              FractionallySizedBox(
                widthFactor: i.isEven ? 0.9 : 0.6,
                child: const Skeleton(height: 13),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.mascot = MascotState.welcome,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? message;
  final MascotState mascot;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopIn(
              child: FloatIdle(
                amplitude: 5,
                child: Mascot(state: mascot, size: 150, animate: false),
              ),
            ),
            const SizedBox(height: 20),
            Reveal(
              index: 1,
              child: Text(
                title,
                style: t.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Reveal(
                index: 2,
                child: Text(
                  message!,
                  style: t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              Reveal(
                index: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 300,
                  ),
                  child: PrimaryButton(
                    label: actionLabel!,
                    onPressed: onAction,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.message, required this.onRetry});

  /// Defaults to a generic "something went wrong".
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return EmptyState(
      title: s.errorTitle,
      message: message ?? s.somethingWentWrong,
      mascot: MascotState.error,
      actionLabel: s.tryAgain,
      onAction: onRetry,
    );
  }
}

/// A sentence the owner can act on, never a raw exception.
///
/// Known failures get a specific message. Short plain sentences (in
/// English) pass through; anything that looks technical never reaches the
/// screen.
String friendlyError(Object e, [S s = S.en]) {
  final raw = e.toString();
  final lower = raw.toLowerCase();
  if (e is ApiException && e.isNetwork) return s.errOffline;
  if (lower.contains('not found')) return s.errNotFound;
  if (lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    return s.errOffline;
  }
  if (raw.contains('rate_limit') || raw.contains('Too many OTP requests')) {
    return s.errRateLimit;
  }
  if (raw.contains('invalid_otp') ||
      raw.contains('Invalid OTP') ||
      raw.contains('Invalid or expired')) {
    return s.errInvalidOtp;
  }
  if (raw.contains('otp_locked')) return s.errOtpLocked;
  if (raw.contains('phone_registered') || raw.contains('already exists')) {
    return s.errPhoneRegistered;
  }
  if (e is ApiException && e.isAuth) return s.errSessionExpired;
  // Plain sentences from our own code (e.g. "Microphone access is needed.")
  // are fine to show in English; anything that looks technical is not.
  final technical = RegExp(
    r'Exception|Error|expected|received|null|undefined|status code|\{|\[|_',
  );
  if (s.isEn && raw.length < 90 && !technical.hasMatch(raw)) return raw;
  return s.somethingWentWrong;
}

/// AsyncValue → loading / error / data, crossfading between the three.
/// Data keeps showing while a refresh is in flight.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (value.hasValue) {
      child = KeyedSubtree(
        key: const ValueKey('data'),
        child: data(value.value as T),
      );
    } else if (value.hasError) {
      child = KeyedSubtree(
        key: const ValueKey('error'),
        child: ErrorState(
          message: friendlyError(value.error!, context.s),
          onRetry: onRetry ?? () {},
        ),
      );
    } else {
      child = KeyedSubtree(
        key: const ValueKey('loading'),
        child: loading ?? const SkeletonList(),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.base),
      switchInCurve: AppMotion.standard,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

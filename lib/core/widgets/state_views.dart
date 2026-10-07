import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'mascot.dart';

/// Shimmering skeleton block (cheap: single animation shared per list).
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
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
    child: Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    ),
  );
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3, this.height});
  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
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

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 4,
    this.padding = const EdgeInsets.all(AppSpace.page),
  });
  final int count;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ListView.separated(
    physics: const NeverScrollableScrollPhysics(),
    padding: padding,
    itemCount: count,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, _) => const SkeletonCard(),
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
            Mascot(state: mascot, size: 150),
            const SizedBox(height: 20),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: t.bodyMedium, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 260,
                child: PrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.message = 'Something went wrong. Try again.',
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'Hmm, that didn\'t work',
    message: message,
    mascot: MascotState.error,
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('not found')) {
    return 'We couldn\'t find that. It may have been removed.';
  }
  if (s.contains('connection') || s.contains('network')) {
    return 'No connection. Check your internet and try again.';
  }
  if (s.contains('rate_limit') || s.contains('Too many OTP requests')) {
    return 'Too many attempts. Please wait 10 minutes before requesting a new code.';
  }
  if (s.contains('invalid_otp') ||
      s.contains('Invalid OTP') ||
      s.contains('Invalid or expired')) {
    return 'Invalid or expired OTP. Please check the code and try again.';
  }
  if (s.contains('otp_locked')) {
    return 'Too many failed attempts. Please request a new OTP.';
  }
  if (s.contains('phone_registered') || s.contains('already exists')) {
    return 'This phone number is already registered. Please sign in instead.';
  }
  if (s.length < 90 && !s.contains('Exception') && !s.contains('Error')) {
    return s;
  }
  return 'Something went wrong. Try again.';
}

/// AsyncValue → loading / error / data with consistent visuals.
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
    if (value.hasValue) return data(value.value as T);
    if (value.hasError) {
      return ErrorState(
        message: friendlyError(value.error!),
        onRetry: onRetry ?? () {},
      );
    }
    return loading ?? const SkeletonList();
  }
}

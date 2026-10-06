import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/brand.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_widgets.dart';

/// Branded launch screen: "CallPilot · Your AI Calling Employee".
/// Continues the native splash (same background + mark) for a seamless start.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1300), () async {
      if (!mounted) return;
      final isMock = ref.read(useMockProvider);
      final hasSession = await ref.read(authRepoProvider).hasSession();
      if (!mounted) return;
      if (!isMock && !hasSession) {
        context.go('/login');
      } else {
        context.go(ref.read(localPrefsProvider).onboarded ? '/home' : '/onboarding');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
          ),
          child: Semantics(
            label: '${Brand.appName}. ${Brand.tagline}',
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 96),
                  const SizedBox(height: 22),
                  Text(Brand.appName, style: t.displaySmall?.copyWith(fontSize: 38, letterSpacing: -1)),
                  const SizedBox(height: 6),
                  Text(
                    Brand.tagline,
                    style: t.titleMedium?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

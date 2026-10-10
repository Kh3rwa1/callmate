import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/brand.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../l10n/l10n.dart';

/// Where the app goes once launch (and the first-launch language pick) is
/// done: sign in, set up the employee, or straight home.
Future<void> goAfterLaunch(BuildContext context, WidgetRef ref) async {
  final isMock = ref.read(useMockProvider);
  final hasSession = await ref.read(authRepoProvider).hasSession();
  if (!context.mounted) return;
  if (!isMock && !hasSession) {
    context.go('/login');
  } else {
    context.go(
      ref.read(localPrefsProvider).onboarded ? '/home' : '/onboarding',
    );
  }
}

/// Branded launch screen: "CallPilot · Your AI Calling Employee".
/// Continues the native splash (same background + mark): the mark pops,
/// the name rises in, then the tagline.
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
      final prefs = ref.read(localPrefsProvider);
      // First launch: the language comes before any English word.
      if (prefs.language == null && !prefs.onboarded) {
        context.go('/language');
        return;
      }
      await goAfterLaunch(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Semantics(
          label: '${Brand.appName}. ${s.tagline}',
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PopIn(
                  duration: Duration(milliseconds: 620),
                  child: BrandMark(size: 96),
                ),
                const SizedBox(height: 22),
                Reveal(
                  index: 4,
                  stagger: const Duration(milliseconds: 60),
                  child: Text(
                    Brand.appName,
                    style: t.displaySmall?.copyWith(
                      fontSize: 38,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Reveal(
                  index: 6,
                  stagger: const Duration(milliseconds: 60),
                  child: Text(
                    s.tagline,
                    style: t.titleMedium?.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

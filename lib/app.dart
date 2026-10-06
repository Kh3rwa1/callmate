import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/brand.dart';
import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/misc.dart';
import 'data/repositories/repositories.dart' show NotificationEvent;
import 'features/notifications/notifications_screen.dart';

class CallPilotApp extends ConsumerStatefulWidget {
  const CallPilotApp({super.key});
  @override
  ConsumerState<CallPilotApp> createState() => _CallPilotAppState();
}

class _CallPilotAppState extends ConsumerState<CallPilotApp> {
  final _subs = <StreamSubscription<dynamic>>[];
  AppNotification? _banner;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    final notif = ref.read(notificationServiceProvider);

    // Backend → notification (not every call: only actionable events).
    _subs.add(
      ref.read(backendEventsProvider).stream.listen((e) {
        if (e is NotificationEvent) notif.present(e.notification);
      }),
    );

    // Foreground banner.
    _subs.add(
      notif.inApp.listen((n) {
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() => _banner = n);
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _banner = null);
        });
        ref.invalidate(notificationsProvider);
      }),
    );

    // Notification tap (system tray) → deep link.
    _subs.add(notif.taps.listen(_open));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await notif.init();
      final launch = notif.takeLaunchRoute();
      if (launch != null) _open(launch);
    });
  }

  void _open(String route) {
    setState(() => _banner = null);
    final router = ref.read(routerProvider);
    if (route.isEmpty || route.endsWith('/')) {
      router.go('/home');
      return;
    }
    // Keep a sensible back stack: tab first, then the detail.
    if (route.startsWith('/followups/')) {
      router.go('/followups');
    } else if (route.startsWith('/leads/')) {
      router.go('/leads');
    } else if (route.startsWith('/calls/')) {
      router.go('/calls');
    }
    if (route.split('/').length > 2 || route.contains('/campaigns/') || route == '/callbacks') {
      router.push(route);
    } else {
      router.go(route);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Keep the live campaign listener alive app-wide.
    ref.watch(activeCampaignProvider);
    return MaterialApp.router(
      title: Brand.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      builder: (context, child) {
        // Respect user font scaling but cap it so layouts stay usable.
        final mq = MediaQuery.of(context);
        final scaled = mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.35));
        return MediaQuery(
          data: scaled,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: _banner == null ? -140 : mq.padding.top + 8,
                child: _banner == null
                    ? const SizedBox.shrink()
                    : Semantics(
                        liveRegion: true,
                        child: InAppNotificationBanner(
                          n: _banner!,
                          onOpen: () => _open(_banner!.route),
                          onClose: () => setState(() => _banner = null),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

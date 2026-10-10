import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/brand.dart';
import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/routing/deep_link.dart';
import 'core/settings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/palette_scope.dart';
import 'l10n/s.dart';
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
  final _light = AppTheme.light();
  final _dark = AppTheme.dark();
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
    if (!mounted) return;
    setState(() => _banner = null);
    openDeepLink(ref.read(routerProvider), route);
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
    // Keep push notification service initialized when logged in.
    ref.watch(pushServiceInitializerProvider);
    // Keep the live campaign listener alive app-wide.
    ref.watch(activeCampaignProvider);
    return MaterialApp.router(
      title: Brand.appName,
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 260),
      locale: ref.watch(languageProvider)?.locale,
      supportedLocales: AppLang.locales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Any other phone language falls back to English.
      localeResolutionCallback: (device, _) =>
          AppLang.fromCode(device?.languageCode).locale,
      routerConfig: router,
      builder: (context, child) {
        // The phone's font size times the in-app "Text size", up to 2x.
        final mq = MediaQuery.of(context);
        final scaled = mq.copyWith(
          textScaler: appTextScaler(mq.textScaler, ref.watch(textSizeProvider)),
        );
        return PaletteScope(
          child: MediaQuery(
            data: scaled,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: _banner == null
                      ? Curves.easeInCubic
                      : Curves.easeOutBack,
                  left: 0,
                  right: 0,
                  top: _banner == null ? -160 : mq.padding.top + 8,
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
          ),
        );
      },
    );
  }
}

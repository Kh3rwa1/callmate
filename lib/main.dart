import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/bootstrap/firebase_bootstrap.dart';
import 'core/config/app_env.dart';
import 'core/providers.dart';
import 'core/storage/local_prefs.dart';
import 'services/crash/crash_reporting_service.dart';
import 'services/crash/firebase_crash_sink.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseReady = await FirebaseBootstrap.ensureInitialized();
  if (firebaseReady) {
    // Collect only from release builds; debug noise stays local.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      kReleaseMode,
    );
  }
  final crash = SafeCrashReportingService(
    sink: firebaseReady ? FirebaseCrashSink() : null,
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crash.reportError(
      details.exception,
      details.stack,
      reason: details.context?.toString(),
      fatal: true,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.reportError(error, stack, fatal: true);
    return true;
  };

  // Refuse to start a build that points at a placeholder, insecure or
  // missing backend – but show why instead of dying on the splash screen.
  final configError = AppEnv.startupError();
  if (configError != null) {
    crash.reportError(StateError(configError), StackTrace.current, fatal: true);
    runApp(ConfigErrorApp(message: configError));
    return;
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await LocalPrefs.create();

  runApp(
    ProviderScope(
      overrides: [
        localPrefsProvider.overrideWithValue(prefs),
        crashReportingProvider.overrideWithValue(crash),
      ],
      child: const CallPilotApp(),
    ),
  );
}

/// Shown instead of the app when the compiled-in configuration is unusable.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This build is misconfigured',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(message),
            ],
          ),
        ),
      ),
    ),
  );
}

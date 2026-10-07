import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/local_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      overrides: [localPrefsProvider.overrideWithValue(prefs)],
      child: const CallPilotApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/env.dart';
import 'data/api_client.dart';
import 'data/app_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const CallmateApp());
}

class CallmateApp extends StatelessWidget {
  const CallmateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppRepository(ApiClient())..load(),
      child: MaterialApp(
        title: 'Callmate AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Env.isConfigured ? const AppShell() : const NotConfiguredScreen(),
      ),
    );
  }
}

/// Shown when the app was built without backend configuration, so the failure is
/// explained rather than appearing as an unexpected network error.
class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 48, color: AppColors.inkSoft),
                const SizedBox(height: 16),
                Text('Connect your backend', style: AppText.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Build the app with your Supabase URL and anon key to get started:\n\n'
                  'flutter run --dart-define=SUPABASE_URL=… '
                  '--dart-define=SUPABASE_ANON_KEY=…',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

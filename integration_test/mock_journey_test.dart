import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:callpilot/app.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end mock user journey boots cleanly into CallPilotApp', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final prefs = await SharedPreferences.getInstance();
    final localPrefs = LocalPrefs(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useMockProvider.overrideWithValue(true),
          localPrefsProvider.overrideWithValue(localPrefs),
        ],
        child: const CallPilotApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(CallPilotApp), findsOneWidget);
  });
}

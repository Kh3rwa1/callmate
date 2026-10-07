import 'package:callpilot/core/config/app_env.dart';
import 'package:callpilot/core/storage/local_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppEnv.configError', () {
    String? check(AppFlavor flavor, String url, {bool mock = false}) =>
        AppEnv.configError(flavor: flavor, useMock: mock, apiBaseUrl: url);

    test('dev builds are never blocked', () {
      expect(check(AppFlavor.dev, ''), isNull);
      expect(check(AppFlavor.dev, 'http://127.0.0.1:8787'), isNull);
      expect(check(AppFlavor.dev, 'https://api.example.com'), isNull);
    });

    test('mock builds are never blocked, whatever the flavor', () {
      expect(check(AppFlavor.prod, '', mock: true), isNull);
      expect(check(AppFlavor.staging, 'http://x', mock: true), isNull);
    });

    for (final flavor in [AppFlavor.prod, AppFlavor.staging]) {
      group(flavor.name, () {
        test('accepts a real https URL', () {
          expect(check(flavor, 'https://api.callpilot.in'), isNull);
          expect(check(flavor, 'https://api.callpilot.in/v1/'), isNull);
        });

        test('rejects an empty URL', () {
          final e = check(flavor, '  ');
          expect(e, contains('empty'));
          expect(e, contains('env/${flavor.name}.json'));
        });

        test('rejects non-https URLs', () {
          expect(check(flavor, 'http://api.callpilot.in'), contains('https'));
          expect(check(flavor, 'api.callpilot.in'), contains('https'));
          expect(check(flavor, 'https://'), contains('https'));
        });

        test('rejects example.com placeholders', () {
          expect(
            check(flavor, 'https://api.example.com'),
            contains('placeholder'),
          );
          expect(
            check(flavor, 'https://staging-api.EXAMPLE.com/'),
            contains('placeholder'),
          );
          expect(check(flavor, 'https://example.com'), contains('placeholder'));
        });

        test('does not flag look-alike real domains', () {
          expect(check(flavor, 'https://notexample.com'), isNull);
        });
      });
    }
  });

  test('ensureValid passes for the default (dev) test configuration', () {
    expect(AppEnv.flavor, AppFlavor.dev);
    expect(AppEnv.ensureValid, returnsNormally);
  });

  test('default runtime configuration exposes only proxy settings', () {
    expect(AppEnv.sarvamProxyPath, '/voice/sarvam-proxy/');
    expect(AppEnv.useMock, isFalse);
    expect(AppEnv.showDemoTools, isFalse);
    expect(AppEnv.effectiveApiBaseUrl, startsWith('http://'));
  });

  group('LocalPrefs', () {
    test('create() purges a Sarvam key left by older builds', () async {
      SharedPreferences.setMockInitialValues({
        'config.sarvam_key': 'sk_live_leaked',
        'onboarding.completed': true,
      });
      final prefs = await LocalPrefs.create();
      final raw = await SharedPreferences.getInstance();
      expect(raw.containsKey('config.sarvam_key'), isFalse);
      expect(prefs.onboarded, isTrue);
    });

    test('flags and server URL round-trip; reset clears onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await LocalPrefs.create();
      expect(prefs.onboarded, isFalse);
      expect(prefs.agentTested, isFalse);
      await prefs.setOnboarded(true);
      await prefs.setAgentTested(true);
      await prefs.setServerUrl('https://my.server');
      expect(prefs.onboarded, isTrue);
      expect(prefs.agentTested, isTrue);
      expect(prefs.serverUrl, 'https://my.server');

      await prefs.reset();
      expect(prefs.onboarded, isFalse);
      expect(prefs.agentTested, isFalse);
      expect(prefs.serverUrl, 'https://my.server');
      await prefs.setServerUrl(null);
      expect(prefs.serverUrl, isNull);
    });
  });
}

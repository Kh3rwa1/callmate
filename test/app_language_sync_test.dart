import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/settings.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _RecordingBusinessRepo extends MockBusinessRepository {
  _RecordingBusinessRepo(super.b);
  static final sent = <String>[];
  @override
  Future<void> setAppLanguage(String code) async => sent.add(code);
}

void main() {
  setUp(_RecordingBusinessRepo.sent.clear);

  appTest(
    'the owner picking Hindi tells the server once',
    (h) async {
      // First signed-in launch sends the phone's language.
      expect(_RecordingBusinessRepo.sent, ['en']);
      await h.container.read(languageProvider.notifier).set(AppLang.hi);
      await h.settle();
      expect(_RecordingBusinessRepo.sent, ['en', 'hi']);
      expect(h.prefs.syncedAppLanguage, 'hi');

      // Nothing new to say: no request.
      h.container.invalidate(appLanguageSyncProvider);
      await h.settle();
      expect(_RecordingBusinessRepo.sent, ['en', 'hi']);
    },
    overrides: () => [
      businessRepoProvider.overrideWith(
        (ref) => _RecordingBusinessRepo(ref.watch(mockBackendProvider)),
      ),
    ],
  );
}

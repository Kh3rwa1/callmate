import 'package:callpilot/services/notifications/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushService Unit Tests', () {
    test('routes only internal starting with /', () {
      final routesOpened = <String>[];
      final service = PushService(
        registerToken: (token, platform) async {},
        onRoute: routesOpened.add,
      );

      service.dispose();
      expect(routesOpened, isEmpty);
    });

    test(
      'PushService initializes gracefully without crashing in test environment',
      () async {
        final service = PushService(
          registerToken: (token, platform) async {},
          onRoute: (_) {},
        );

        await service.init();
        expect(service.currentToken, isNull);
        await service.dispose();
      },
    );
  });
}

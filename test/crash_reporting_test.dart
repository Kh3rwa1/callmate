import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/services/crash/crash_reporting_service.dart';

void main() {
  group('SafeCrashReportingService PII scrubbing', () {
    test(
      'scrubs phone numbers, bearer tokens, JWTs, and emails from strings',
      () {
        const input =
            'Call failed for user +919830012345 (also 9876543210) with auth Header: Bearer eyJhbGciOiJIUzI1NiJ9.test.sig and email client@example.com';
        final scrubbed = SafeCrashReportingService.scrubPii(input);

        expect(scrubbed.contains('+919830012345'), isFalse);
        expect(scrubbed.contains('9876543210'), isFalse);
        expect(scrubbed.contains('client@example.com'), isFalse);
        expect(scrubbed.contains('eyJhbGciOiJIUzI1NiJ9'), isFalse);
        expect(scrubbed, contains('[PHONE_REDACTED]'));
        expect(scrubbed, contains('[EMAIL_REDACTED]'));
        expect(scrubbed, contains('Bearer [TOKEN_REDACTED]'));
      },
    );

    test('scrubs blocked keys from context maps', () {
      final service = SafeCrashReportingService(enabled: true);
      final raw = {
        'phone': '+919830012345',
        'transcript': 'User said I am interested',
        'route': '/leads/123',
        'status_code': 500,
        'info': 'Failed to reach lead 9812345678',
      };

      final scrubbed = service.scrubContext(raw);

      expect(scrubbed.containsKey('phone'), isFalse);
      expect(scrubbed.containsKey('transcript'), isFalse);
      expect(scrubbed['route'], equals('/leads/123'));
      expect(scrubbed['status_code'], equals(500));
      expect(scrubbed['info'], equals('Failed to reach lead [PHONE_REDACTED]'));
    });

    test('silences reporting when enabled is false', () {
      final service = SafeCrashReportingService(enabled: false);
      expect(service.enabled, isFalse);
      // reportError and log should safely execute as no-ops
      service.reportError(Exception('error with 9876543210'), null);
      service.log('message with 9876543210');
    });
  });
}

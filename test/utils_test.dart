import 'package:callpilot/core/utils/csv.dart';
import 'package:callpilot/core/utils/format.dart';
import 'package:callpilot/core/utils/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt', () {
    final now = DateTime(2026, 10, 7, 15, 30);

    test('time uses 12-hour clock', () {
      expect(Fmt.time(DateTime(2026, 1, 1, 18)), '6:00 PM');
      expect(Fmt.time(DateTime(2026, 1, 1, 9, 5)), '9:05 AM');
    });

    test('duration pads minutes/seconds and adds hours when needed', () {
      expect(Fmt.duration(const Duration(seconds: 7)), '00:07');
      expect(Fmt.duration(const Duration(minutes: 3, seconds: 42)), '03:42');
      expect(
        Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('relative covers every bucket', () {
      expect(
        Fmt.relative(now.subtract(const Duration(seconds: 10)), now: now),
        'just now',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(Fmt.relative(DateTime(2026, 10, 6, 20), now: now), 'Yesterday');
      expect(Fmt.relative(DateTime(2026, 9, 1, 12), now: now), '1 Sep');
      // Future dates are rendered as friendly future phrases.
      expect(
        Fmt.relative(DateTime(2026, 10, 8, 18), now: now),
        'Tomorrow, 6:00 PM',
      );
    });

    test('friendlyFuture labels today / tomorrow / yesterday / other', () {
      expect(
        Fmt.friendlyFuture(DateTime(2026, 10, 7, 18), now: now),
        'Today, 6:00 PM',
      );
      expect(
        Fmt.friendlyFuture(DateTime(2026, 10, 8, 18), now: now),
        'Tomorrow, 6:00 PM',
      );
      expect(
        Fmt.friendlyFuture(DateTime(2026, 10, 6, 18), now: now),
        'Yesterday, 6:00 PM',
      );
      expect(
        Fmt.friendlyFuture(DateTime(2026, 10, 10, 18), now: now),
        'Sat, 10 Oct · 6:00 PM',
      );
    });

    test('callbackPhrase reads naturally', () {
      expect(
        Fmt.callbackPhrase(DateTime(2026, 10, 7, 18), now: now),
        'today at 6:00 PM',
      );
      expect(
        Fmt.callbackPhrase(DateTime(2026, 10, 8, 18), now: now),
        'tomorrow at 6:00 PM',
      );
      expect(
        Fmt.callbackPhrase(DateTime(2026, 10, 10, 18), now: now),
        'on Sat, 10 Oct at 6:00 PM',
      );
    });

    test('inr and number use Indian digit grouping', () {
      expect(Fmt.inr(5200000), '₹52,00,000');
      expect(Fmt.inr(499), '₹499');
      expect(Fmt.number(1234567), '12,34,567');
    });

    test('greeting depends on hour', () {
      expect(Fmt.greeting(DateTime(2026, 1, 1, 8)), 'Good morning');
      expect(Fmt.greeting(DateTime(2026, 1, 1, 13)), 'Good afternoon');
      expect(Fmt.greeting(DateTime(2026, 1, 1, 20)), 'Good evening');
      expect(Fmt.greeting(), isNotEmpty);
    });

    test('hour formats an hour of the day', () {
      expect(Fmt.hour(10), '10 AM');
      expect(Fmt.hour(19), '7 PM');
    });
  });

  group('PhoneUtils', () {
    test('null / whitespace input is invalid', () {
      expect(PhoneUtils.normalize(null), isNull);
      expect(PhoneUtils.normalize('   '), isNull);
      expect(PhoneUtils.normalize('+'), isNull);
      expect(PhoneUtils.isValid(null), isFalse);
      expect(PhoneUtils.isValid('9876543210'), isTrue);
    });

    test('honours a custom country code for 10-digit numbers', () {
      expect(
        PhoneUtils.normalize('2025550123', countryCode: '1'),
        '12025550123',
      );
    });

    test('rejects too-long numbers and leading-zero international', () {
      expect(PhoneUtils.normalize('+1234567890123456'), isNull);
      expect(PhoneUtils.normalize('+0441234567'), isNull);
    });

    test('display falls back to raw text when invalid', () {
      expect(PhoneUtils.display('hello'), 'hello');
      expect(PhoneUtils.display(null), '');
      expect(PhoneUtils.display('+44 7700 900123'), '+447700900123');
    });

    test('masked hides the middle digits', () {
      expect(PhoneUtils.masked('9876543210'), '+9198•••••210');
      expect(PhoneUtils.masked('bad'), '•••');
    });
  });

  group('CsvLeadParser', () {
    test('parse handles escaped quotes, CRLF, ; and tab separators', () {
      final rows = CsvLeadParser.parse(
        'a,"say ""hi""",c\r\nd;e\tf\n\n  ,  \ng',
      );
      expect(rows, [
        ['a', 'say "hi"', 'c'],
        ['d', 'e', 'f'],
        ['g'],
      ]);
    });

    test('sanitize strips formula prefixes, control chars and caps length', () {
      expect(CsvLeadParser.sanitize('=+-@SUM(A1)'), 'SUM(A1)');
      expect(CsvLeadParser.sanitize('a\tb\x00c'), 'a b c');
      expect(CsvLeadParser.sanitize('<script>'), 'script');
      expect(CsvLeadParser.sanitize('x' * 500).length, 120);
    });

    test('empty input reports an error', () {
      final r = CsvLeadParser.toLeads('\n\n');
      expect(r.leads, isEmpty);
      expect(r.errors, ['The file is empty.']);
    });

    test('headerless files are read as name, phone', () {
      final r = CsvLeadParser.toLeads(
        'Priya Das,9831022233\nAmit,9874033344\n',
      );
      expect(r.leads.map((e) => e.name), ['Priya Das', 'Amit']);
      expect(r.leads.first.source, 'CSV import');
      expect(r.leads.first.interest, isNull);
    });

    test('detects source column and names blank leads by masked phone', () {
      final r = CsvLeadParser.toLeads(
        'Customer,WhatsApp,Course,Channel\n'
        ',9831022233,NEET,Facebook\n',
      );
      final l = r.leads.single;
      expect(l.name, startsWith('Lead +91'));
      expect(l.interest, 'NEET');
      expect(l.source, 'Facebook');
    });

    test('caps the number of reported errors at five', () {
      final rows = List.generate(8, (i) => 'Bad $i,123').join('\n');
      final r = CsvLeadParser.toLeads('Name,Phone\n$rows');
      expect(r.skipped, 8);
      expect(r.errors, hasLength(5));
      expect(r.errors.first, 'Row 2: invalid phone number');
    });
  });
}

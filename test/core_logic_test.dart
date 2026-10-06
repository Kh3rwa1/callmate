import 'package:flutter_test/flutter_test.dart';
import 'package:riya_admissions/core/utils/csv.dart';
import 'package:riya_admissions/core/utils/phone.dart';
import 'package:riya_admissions/data/datasources/mock/mock_backend.dart';
import 'package:riya_admissions/data/datasources/mock/mock_repositories.dart';
import 'package:riya_admissions/data/models/ai_output.dart';
import 'package:riya_admissions/data/models/models.dart';
import 'package:riya_admissions/services/whatsapp/whatsapp_service.dart';

void main() {
  group('PhoneUtils', () {
    test('normalises common Indian formats', () {
      for (final input in ['98765 43210', '+91-98765-43210', '09876543210', '919876543210', '0091 98765 43210', '(+91) 98765.43210']) {
        expect(PhoneUtils.normalize(input), '919876543210', reason: input);
      }
    });
    test('rejects invalid numbers', () {
      for (final input in ['12345', '', 'abc', '5876543210', '+91 12345 67890', '91987654321']) {
        expect(PhoneUtils.normalize(input), isNull, reason: input);
      }
    });
    test('keeps valid international numbers', () {
      expect(PhoneUtils.normalize('+44 7700 900123'), '447700900123');
    });
    test('display + mask', () {
      expect(PhoneUtils.display('9876543210'), '+91 98765 43210');
      expect(PhoneUtils.masked('9876543210'), isNot(contains('6543')));
    });
  });

  group('WhatsApp deep link', () {
    test('builds wa.me URL with encoded message', () {
      final uri = WhatsAppDeepLinkService.buildUri(phone: '98765 43210', message: 'Hi Rahul 👋\nFees: ₹52,000 & more?');
      expect(uri.toString(), startsWith('https://wa.me/919876543210?text='));
      expect(Uri.decodeComponent(uri!.query.substring(5)), 'Hi Rahul 👋\nFees: ₹52,000 & more?');
      expect(uri.toString(), isNot(contains(' ')));
      expect(uri.toString(), isNot(contains('&more')));
    });
    test('invalid phone → null', () {
      expect(WhatsAppDeepLinkService.buildUri(phone: '123', message: 'x'), isNull);
    });
  });

  group('CSV import', () {
    test('parses header, quotes, sanitises and dedupes', () {
      const csv =
          'Name,Mobile,Course\n'
          '"Das, Priya",98310 22233,JEE Main\n'
          '=HYPERLINK("x"),9831022233,NEET\n'
          'Bad,123,NEET\n'
          'Ankit <b>Singh</b>,+91 98740 33344,"WBJEE"\n';
      final r = CsvLeadParser.toLeads(csv);
      expect(r.leads.length, 2);
      expect(r.leads.first.name, 'Das, Priya');
      expect(r.leads.first.phone, '919831022233');
      expect(r.leads[1].name, isNot(contains('<')));
      expect(r.skipped, 2); // duplicate + invalid
    });
  });

  group('AI structured output', () {
    test('parses and clamps', () {
      final o = AiCallOutput.fromJson({
        'lead_score': 140,
        'intent': 'interested',
        'summary': 's',
        'next_action': 'counsellor_callback',
        'whatsapp_followup_required': true,
      });
      expect(o.leadScore, 100);
      expect(o.temperature, LeadTemperature.hot);
      expect(o.nextAction, NextAction.counsellorCallback);
    });
    test('unknown enum values degrade gracefully', () {
      final l = Lead.fromJson({'id': '1', 'status': 'weird', 'next_action': '???'});
      expect(l.status, LeadStatus.newLead);
      expect(l.nextAction, NextAction.none);
    });
  });

  group('Mock backend pipeline', () {
    test('seed matches demo story', () {
      final b = MockBackend();
      expect(b.leads.values.any((l) => l.name == 'Rahul Kumar' && l.score?.value == 87), isTrue);
      expect(b.followUps.values.where((f) => f.isPending).length, 18);
      expect(b.leads.values.where((l) => l.isHot).length, greaterThanOrEqualTo(6));
      b.dispose();
    });

    test('simulated hot call → score + follow-up + callback + notification', () async {
      final b = MockBackend();
      final events = <Object>[];
      final sub = b.stream.listen(events.add);
      final call = b.simulateCall(LeadTemperature.hot);
      await Future<void>.delayed(Duration.zero);
      expect(call.status, CallStatus.completed);
      expect(call.leadScore!.value, greaterThanOrEqualTo(75));
      expect(call.followUpId, isNotNull);
      expect(b.followUps[call.followUpId]!.message, contains(b.leads[call.leadId]!.firstName));
      expect(b.callbacks.values.any((c) => c.leadId == call.leadId), isTrue);
      expect(events.whereType<Object>().any((e) => e.toString().contains('NotificationEvent')), isTrue);
      await sub.cancel();
      b.dispose();
    });

    test('lead pagination', () async {
      final b = MockBackend();
      final repo = MockLeadRepository(b);
      final p1 = await repo.list(limit: 20);
      final p2 = await repo.list(limit: 20, cursor: p1.nextCursor);
      expect(p1.items.length, 20);
      expect(p1.hasMore, isTrue);
      expect(p1.items.first.isHot, isTrue); // hot first
      expect(p2.items.map((e) => e.id).toSet().intersection(p1.items.map((e) => e.id).toSet()), isEmpty);
      b.dispose();
    });
  });
}

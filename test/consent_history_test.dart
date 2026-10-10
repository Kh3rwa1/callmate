import 'dart:convert';

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/leads/lead_detail_widgets.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _FakeStore extends SecureStore {
  @override
  Future<String?> accessToken() async => 'jwt';
  @override
  Future<String?> refreshToken() async => 'refresh';
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions o) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

Widget _card(List<ConsentEvent> events) => ProviderScope(
  overrides: [
    leadConsentHistoryProvider('l1').overrideWith((ref) async => events),
  ],
  child: const MaterialApp(
    home: Scaffold(body: ConsentHistoryCard(leadId: 'l1')),
  ),
);

void main() {
  test('ConsentEvent.fromJson reads the API shape and tolerates gaps', () {
    final e = ConsentEvent.fromJson({
      'id': 'ce_1',
      'consent_value': 'opt_out',
      'source': 'in_call_opt_out',
      'text_version': 'opt-out-detector-v1',
      'created_at': '2026-10-09 01:29:20',
    });
    expect(e.consentValue, 'opt_out');
    expect(e.source, 'in_call_opt_out');
    expect(e.textVersion, 'opt-out-detector-v1');
    expect(e.createdAt.toUtc(), DateTime.utc(2026, 10, 9, 1, 29, 20));

    final bare = ConsentEvent.fromJson({'id': 'x'});
    expect(bare.consentValue, 'unknown');
    expect(bare.source, 'manual');
    expect(bare.textVersion, isNull);
  });

  test(
    'ApiLeadRepository.consentHistory calls the consent-history endpoint',
    () async {
      final client = ApiClient(_FakeStore(), baseUrl: 'https://api.test');
      String? path;
      client.dio.httpClientAdapter = _Adapter((o) {
        path = o.path;
        return ResponseBody.fromString(
          jsonEncode({
            'items': [
              {
                'id': 'ce_1',
                'consent_value': 'inquiry',
                'source': 'form',
                'created_at': '2026-10-09 01:29:20',
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final events = await ApiLeadRepository(client).consentHistory('l1');
      expect(path, '/leads/l1/consent-history');
      expect(events.single.source, 'form');
    },
  );

  test(
    'MockLeadRepository.consentHistory describes how the lead was added',
    () async {
      final b = MockBackend();
      final repo = MockLeadRepository(b);
      final lead = b.leads.values.first;
      b.leads[lead.id] = lead.copyWith(consent: 'opt_out');
      final events = await repo.consentHistory(lead.id);
      expect(events.first.source, 'in_call_opt_out');
      expect(events.last.consentValue, 'unknown');
      expect(() => repo.consentHistory('missing'), throwsStateError);
    },
  );

  test('consent labels exist in English, Hindi and Bengali', () {
    const values = [
      'explicit_opt_in',
      'inquiry',
      'existing_customer',
      'owner_attested',
      'opt_out',
      'do_not_call',
      'do_not_call_removed',
      'unknown',
    ];
    const sources = [
      'form',
      'webhook',
      'import_attestation',
      'in_call_opt_out',
      'manual',
    ];
    for (final lang in AppLang.values) {
      final s = S(lang);
      expect(s.consentHistory, isNotEmpty);
      expect(s.consentHistoryEmpty, isNotEmpty);
      expect(values.map(s.consentValue).toSet(), hasLength(values.length));
      expect(sources.map(s.consentSource).toSet(), hasLength(sources.length));
    }
    expect(const S(AppLang.hi).consentHistory, 'सहमति का रिकॉर्ड');
    expect(const S(AppLang.bn).consentHistory, 'সম্মতির রেকর্ড');
  });

  testWidgets('ConsentHistoryCard lists events', (tester) async {
    await tester.pumpWidget(
      _card([
        ConsentEvent(
          id: '2',
          consentValue: 'opt_out',
          source: 'in_call_opt_out',
          createdAt: DateTime.utc(2026, 10, 9),
        ),
        ConsentEvent(
          id: '1',
          consentValue: 'inquiry',
          source: 'form',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asked not to be called'), findsOneWidget);
    expect(find.text('Said so on a call'), findsOneWidget);
    expect(find.text('Made an enquiry'), findsOneWidget);
    expect(find.text('Enquiry form'), findsOneWidget);
  });

  testWidgets('ConsentHistoryCard shows an empty state', (tester) async {
    await tester.pumpWidget(_card(const []));
    await tester.pumpAndSettle();
    expect(find.text('No consent changes recorded yet.'), findsOneWidget);
  });

  group('LeadDetailScreen consent history', () {
    appTest('shows the lead\'s consent history', (h) async {
      final lead = h.backend.leads.values.first;
      await h.push('/leads/${lead.id}');
      await h.tester.scrollUntilVisible(
        find.text('Consent history'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byType(ConsentHistoryCard), findsOneWidget);
    });
  });
}

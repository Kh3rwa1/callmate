import 'dart:convert';

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/core/widgets/lead_widgets.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/leads/lead_integrations.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _FakeStore extends SecureStore {
  @override
  Future<String?> accessToken() async => 'jwt';
  @override
  Future<String?> refreshToken() async => 'refresh';
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);
  final Future<ResponseBody> Function(RequestOptions o) responder;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) => responder(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// Fails every create with a server error (to show it inside the sheet).
class _RejectingSources extends MockLeadSourceRepository {
  _RejectingSources(super.b);
  @override
  Future<LeadSource> create(
    LeadSourceKind kind, {
    LeadSourceSecrets secrets = const LeadSourceSecrets(),
  }) async => throw const ApiException(
    'Integrations are not configured on the server yet.',
    statusCode: 503,
    code: 'not_configured',
  );
}

List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  const s = S.en;

  group('Connect a lead source', () {
    appTest('shows Google Ads, IndiaMART and Facebook tiles, not connected', (
      h,
    ) async {
      expect(find.text(s.connectLeadSource), findsOneWidget);
      for (final k in integrationKinds) {
        expect(find.byKey(Key('lead-source-tile-${k.wire}')), findsOne);
        expect(find.byKey(Key('lead-source-connect-${k.wire}')), findsOne);
      }
      expect(find.text(s.googleAdsName), findsOneWidget);
      expect(find.text(s.indiaMartName), findsOneWidget);
      expect(find.text(s.metaName), findsOneWidget);
    }, location: '/leads/auto');

    appTest(
      'Google Ads: steps, connect, URL + key shown once with copy buttons',
      (h) async {
        final copied = _captureClipboard(h.tester);
        await h.tap(find.byKey(const Key('lead-source-connect-google_ads')));
        expect(find.byKey(const Key('integration-sheet-google_ads')), findsOne);
        expect(find.text(s.googleAdsSteps.first), findsOneWidget);

        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        expect(find.byKey(const Key('integration-sheet-connected')), findsOne);
        final src = h.backend.leadSources.single;
        expect(src.kind, LeadSourceKind.googleAds);
        expect(src.url, contains('/hooks/google-ads/'));
        final key = h.tester
            .widget<SelectableText>(
              find.byKey(const Key('integration-sheet-field-token')),
            )
            .data!;
        expect(key, startsWith('cpga'));

        await h.tap(find.byKey(const Key('integration-sheet-copy-url')));
        await h.tap(find.byKey(const Key('integration-sheet-copy-token')));
        expect(copied, [src.url, key]);
        expect(find.byKey(const Key('integration-sheet-copied')), findsOne);

        await h.tap(find.byKey(const Key('integration-sheet-done')));
        expect(find.textContaining(key), findsNothing);
        expect(find.text('${s.connected} · ${s.enquiriesCount(0)}'), findsOne);
        // Connected sources are not listed as website connections.
        expect(find.byKey(Key('lead-capture-webhook-${src.id}')), findsNothing);

        await h.tap(find.byKey(Key('lead-capture-autocall-${src.id}')));
        expect(h.backend.leadSources.single.autoCall, isFalse);

        await h.tap(find.byKey(Key('lead-capture-revoke-${src.id}')));
        await h.tap(find.byKey(const Key('lead-capture-confirm-revoke')));
        expect(h.backend.leadSources, isEmpty);
        expect(
          find.byKey(const Key('lead-source-connect-google_ads')),
          findsOne,
        );
      },
      location: '/leads/auto',
    );

    appTest(
      'IndiaMART: needs the CRM key (error in the sheet), then shows push URL',
      (h) async {
        await h.tap(find.byKey(const Key('lead-source-connect-indiamart')));
        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        expect(find.byKey(const Key('integration-sheet-error')), findsOne);
        expect(find.text(s.crmKeyMissing), findsOneWidget);
        expect(h.backend.leadSources, isEmpty);

        await h.tester.enterText(
          find.byKey(const Key('integration-sheet-crm-key')),
          'mRyxEbBs4HfGTfeq4XaN7lmGp1XNnzI=',
        );
        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        expect(find.byKey(const Key('integration-sheet-error')), findsNothing);
        final src = h.backend.leadSources.single;
        expect(src.kind, LeadSourceKind.indiaMart);
        final push = h.tester
            .widget<SelectableText>(
              find.byKey(const Key('integration-sheet-field-push')),
            )
            .data!;
        expect(push, startsWith('${src.url}?key=cpim'));
        await h.tap(find.byKey(const Key('integration-sheet-done')));
        expect(find.textContaining('Last checked'), findsOneWidget);
      },
      location: '/leads/auto',
    );

    appTest(
      'Facebook & Instagram: validates secrets, shows callback URL + verify token',
      (h) async {
        await h.tap(find.byKey(const Key('lead-source-connect-meta')));
        await h.tester.enterText(
          find.byKey(const Key('integration-sheet-app-secret')),
          'not a secret!',
        );
        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        expect(find.text(s.metaSecretsInvalid), findsOneWidget);

        await h.tester.enterText(
          find.byKey(const Key('integration-sheet-app-secret')),
          'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        );
        await h.tester.enterText(
          find.byKey(const Key('integration-sheet-page-token')),
          'EAAGpagetokenforthetests0123456789',
        );
        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        final src = h.backend.leadSources.single;
        expect(src.kind, LeadSourceKind.meta);
        expect(
          h.tester
              .widget<SelectableText>(
                find.byKey(const Key('integration-sheet-field-url')),
              )
              .data,
          src.url,
        );
        expect(
          h.tester
              .widget<SelectableText>(
                find.byKey(const Key('integration-sheet-field-token')),
              )
              .data,
          startsWith('cpmv'),
        );
      },
      location: '/leads/auto',
    );

    appTest(
      'server errors render inside the sheet',
      (h) async {
        await h.tap(find.byKey(const Key('lead-source-connect-google_ads')));
        await h.tap(find.byKey(const Key('integration-sheet-connect')));
        expect(
          find.text('Integrations are not configured on the server yet.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('integration-sheet-google_ads')), findsOne);
      },
      location: '/leads/auto',
      overrides: () => [
        leadSourceRepoProvider.overrideWith(
          (ref) => _RejectingSources(ref.watch(mockBackendProvider)),
        ),
      ],
    );

    appTest('a broken source shows its problem and reconnecting replaces it', (
      h,
    ) async {
      final src = h.backend.createLeadSource(
        LeadSourceKind.indiaMart,
        secrets: const LeadSourceSecrets(crmKey: 'old-key-123'),
      );
      final i = h.backend.leadSources.indexWhere((x) => x.id == src.id);
      h.backend.leadSources[i] = h.backend.leadSources[i].copyWith(
        lastError: 'invalid_key',
      );
      await h.go('/leads');
      await h.go('/leads/auto');
      expect(find.text(s.sourceProblem('invalid_key')), findsOneWidget);

      await h.tap(find.byKey(Key('lead-source-reconnect-${src.id}')));
      await h.tester.enterText(
        find.byKey(const Key('integration-sheet-crm-key')),
        'new-key-123456',
      );
      await h.tap(find.byKey(const Key('integration-sheet-connect')));
      expect(h.backend.leadSources, hasLength(1));
      expect(h.backend.leadSources.single.id, isNot(src.id));
      expect(h.backend.leadSources.single.hasProblem, isFalse);
    }, location: '/leads/auto');
  });

  group('Demo: IndiaMART enquiry', () {
    appTest('connects IndiaMART if needed, creates the lead, AI calls', (
      h,
    ) async {
      final lead = h.backend.simulateIndiaMartEnquiry(
        callAfter: const Duration(milliseconds: 300),
      );
      expect(lead.source, 'indiamart');
      expect(lead.consent, 'explicit_opt_in');
      expect(lead.interest, startsWith('IndiaMART: '));
      final src = h.backend.leadSources.single;
      expect(src.kind, LeadSourceKind.indiaMart);
      expect(src.leadsCount, 1);
      expect(h.backend.notifications.first.type, NotificationType.newLead);

      await h.settle();
      expect(h.backend.leads[lead.id]!.hasBeenCalled, isTrue);
      h.backend.simulateIndiaMartEnquiry(callAfter: Duration.zero);
      expect(h.backend.leadSources.single.leadsCount, 2);
      await h.settle();

      await h.push('/leads/${lead.id}');
      expect(find.byType(LeadSourceChip), findsOneWidget);
      expect(find.text('IndiaMART'), findsWidgets);
    }, location: '/leads');

    appTest('demo screen has the IndiaMART action', (h) async {
      expect(find.text(s.simulateIndiaMartEnquiry), findsOneWidget);
    }, location: '/demo');
  });

  group('labels', () {
    test('source chips, consent sources, problems in every language', () {
      for (final l in AppLang.values) {
        final t = S(l);
        for (final src in ['google_ads', 'indiamart', 'meta']) {
          expect(t.leadSourceLabel(src), isNotEmpty);
        }
        for (final src in ['google_ads', 'indiamart', 'meta_lead_ads']) {
          expect(t.consentSource(src), isNot(t.consentSource('manual')));
        }
        for (final code in [
          'invalid_key',
          'meta_token_invalid',
          'rate_limited',
          'config_unreadable',
          'upstream_error',
        ]) {
          expect(t.sourceProblem(code), isNotEmpty);
        }
        for (final k in integrationKinds) {
          expect(k.steps(t), hasLength(3));
          expect(k.title(t), isNotEmpty);
          expect(k.hint(t), isNotEmpty);
        }
        expect(t.lastChecked('now'), contains('now'));
      }
      expect(LeadSourceKind.form.steps(s), isEmpty);
      expect(LeadSourceKind.webhook.hint(s), isEmpty);
      expect(LeadSourceKind.webhook.title(s), s.websiteConnection);
      expect(LeadSourceKind.form.icon, isNotNull);
    });

    testWidgets('chips for integration leads', (tester) async {
      Widget app(String source) => MaterialApp(
        home: Scaffold(body: LeadSourceChip(source: source)),
      );
      await tester.pumpWidget(app('google_ads'));
      expect(find.text('Google Ads'), findsOneWidget);
      await tester.pumpWidget(app('meta'));
      expect(find.text('Facebook'), findsOneWidget);
    });
  });

  group('models + API', () {
    test('kind parsing and secrets never send nulls', () {
      expect(LeadSourceKind.parse('google_ads'), LeadSourceKind.googleAds);
      expect(LeadSourceKind.parse('indiamart'), LeadSourceKind.indiaMart);
      expect(LeadSourceKind.parse('meta'), LeadSourceKind.meta);
      expect(LeadSourceKind.parse('nope'), LeadSourceKind.form);
      expect(LeadSourceKind.meta.isIntegration, isTrue);
      expect(LeadSourceKind.webhook.isIntegration, isFalse);
      expect(const LeadSourceSecrets().toJson(), isEmpty);
      expect(const LeadSourceSecrets(crmKey: ' k ', appSecret: '').toJson(), {
        'crm_key': 'k',
      });
      final src = LeadSource.fromJson({
        'id': 'x',
        'kind': 'indiamart',
        'slug': 's',
        'url': 'u',
        'auto_call': true,
        'created_at': '2026-10-09 01:29:20',
        'last_error': 'invalid_key',
        'last_synced_at': '2026-10-09 01:30:00',
      });
      expect(src.hasProblem, isTrue);
      expect(src.lastSyncedAt!.toUtc(), DateTime.utc(2026, 10, 9, 1, 30));
      expect(src.copyWith(clearError: true).hasProblem, isFalse);
      expect(
        MockBackend.leadSourcePath(LeadSourceKind.meta, 'z'),
        '/hooks/meta/z',
      );
    });

    test('ApiLeadSourceRepository sends integration secrets once', () async {
      final bodies = <Object?>[];
      final client = ApiClient(_FakeStore(), baseUrl: 'https://api.test');
      client.dio.httpClientAdapter = _Adapter((o) async {
        bodies.add(o.data);
        return _json({
          'id': 'lsrc_1',
          'kind': 'indiamart',
          'slug': 'AbCdEfGhIjKl',
          'url': 'https://api.test/hooks/indiamart/AbCdEfGhIjKl',
          'auto_call': true,
          'created_at': '2026-10-09 01:29:20',
          'token': 'cpimTOKEN',
          'push_url':
              'https://api.test/hooks/indiamart/AbCdEfGhIjKl?key=cpimTOKEN',
          'last_error': null,
          'last_synced_at': null,
        }, 201);
      });
      final created = await ApiLeadSourceRepository(client).create(
        LeadSourceKind.indiaMart,
        secrets: const LeadSourceSecrets(crmKey: 'KEY12345'),
      );
      expect(bodies.single, {'kind': 'indiamart', 'crm_key': 'KEY12345'});
      expect(created.pushUrl, endsWith('?key=cpimTOKEN'));
      expect(created.lastSyncedAt, isNull);
      expect(created.hasProblem, isFalse);
    });

    test('mock repo rejects bad secrets like the backend', () async {
      final b = MockBackend();
      addTearDown(b.dispose);
      final repo = MockLeadSourceRepository(b);
      await expectLater(
        repo.create(LeadSourceKind.indiaMart),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repo.create(
          LeadSourceKind.meta,
          secrets: const LeadSourceSecrets(
            appSecret: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
            pageAccessToken: 'short',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      final ok = await repo.create(LeadSourceKind.googleAds);
      expect(ok.token, startsWith('cpga'));
      expect(b.leadSources.single.token, isNull);
    });
  });
}

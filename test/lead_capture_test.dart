import 'dart:convert';

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/settings.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/core/widgets/lead_widgets.dart';
import 'package:callpilot/core/widgets/state_views.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/leads/lead_capture_screen.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers/app_harness.dart';

class _FailingSources extends MockLeadSourceRepository {
  _FailingSources(super.b);
  @override
  Future<List<LeadSource>> list() async => throw StateError('network down');
}

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

/// Records Clipboard.setData calls (no platform clipboard in tests).
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

  group('LeadCaptureScreen', () {
    appTest('empty state: create the form link, then copy, QR and toggle', (
      h,
    ) async {
      final copied = _captureClipboard(h.tester);
      expect(find.byKey(const Key('lead-capture-empty')), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);

      await h.tap(find.byKey(const Key('lead-capture-create-form')));
      expect(h.backend.leadSources, hasLength(1));
      final form = h.backend.leadSources.single;
      expect(form.isForm, isTrue);
      expect(find.byKey(const Key('lead-capture-form')), findsOneWidget);
      expect(find.text(form.url), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(s.enquiriesCount(0)), findsOneWidget);

      await h.tap(find.byKey(const Key('lead-capture-copy')));
      expect(copied, [form.url]);
      expect(find.text(s.linkCopied), findsOneWidget);

      await h.tap(find.byKey(Key('lead-capture-autocall-${form.id}')));
      expect(h.backend.leadSources.single.autoCall, isFalse);
      final tile = h.tester.widget<SwitchListTile>(
        find.byKey(Key('lead-capture-autocall-${form.id}')),
      );
      expect(tile.value, isFalse);
    }, location: '/leads/auto');

    appTest(
      'website connection: token shown once in a sheet, copy, then revoke',
      (h) async {
        final copied = _captureClipboard(h.tester);
        await h.tap(find.byKey(const Key('lead-capture-add-webhook')));

        expect(find.byKey(const Key('lead-capture-sheet-warning')), findsOne);
        expect(find.text(s.tokenShownOnce), findsOneWidget);
        final token = (h.tester.widget<SelectableText>(
          find.byKey(const Key('lead-capture-sheet-token')),
        )).data!;
        expect(token, startsWith('cplh_'));

        await h.tap(find.byKey(const Key('lead-capture-sheet-copy-setup')));
        expect(copied.single, contains('Authorization: Bearer $token'));
        // Feedback renders inside the sheet, not as a snackbar behind it.
        expect(find.byKey(const Key('lead-capture-sheet-copied')), findsOne);

        await h.tapText(s.done);
        final hook = h.backend.leadSources.single;
        expect(hook.isForm, isFalse);
        expect(hook.token, isNull, reason: 'the stored source never keeps it');
        expect(
          find.byKey(Key('lead-capture-webhook-${hook.id}')),
          findsOneWidget,
        );
        expect(find.textContaining('cplh_'), findsNothing);

        await h.tap(find.byKey(Key('lead-capture-revoke-${hook.id}')));
        expect(find.text(s.turnOffLinkTitle), findsOneWidget);
        await h.tap(find.byKey(const Key('lead-capture-confirm-revoke')));
        expect(h.backend.leadSources, isEmpty);
        expect(
          find.byKey(Key('lead-capture-webhook-${hook.id}')),
          findsNothing,
        );
      },
      location: '/leads/auto',
    );

    appTest(
      'shows an error with retry when sources fail to load',
      (h) async {
        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byKey(const Key('lead-capture-empty')), findsNothing);
      },
      location: '/leads/auto',
      overrides: () => [
        leadSourceRepoProvider.overrideWith(
          (ref) => _FailingSources(ref.watch(mockBackendProvider)),
        ),
      ],
    );

    appTest('Customers header opens Get leads automatically', (h) async {
      await h.tap(find.byKey(const Key('leads-get-automatically')));
      expect(h.location, '/leads/auto');
      expect(find.byType(LeadCaptureScreen), findsOneWidget);
    }, location: '/leads');

    appTest(
      'renders in Hindi',
      (h) async {
        expect(find.text(const S(AppLang.hi).getLeadsAutomatically), findsOne);
      },
      location: '/leads/auto',
      overrides: () => [
        languageProvider.overrideWith(() => _FixedLang(AppLang.hi)),
      ],
    );
  });

  group('Demo: new form enquiry -> auto call', () {
    appTest('creates an opted-in form lead, notifies, then the AI calls', (
      h,
    ) async {
      final lead = h.backend.simulateFormEnquiry(
        callAfter: const Duration(milliseconds: 300),
      );
      expect(lead.source, 'form');
      expect(lead.consent, 'explicit_opt_in');
      expect(lead.status, LeadStatus.calling);
      expect(h.backend.notifications.first.type, NotificationType.newLead);
      expect(h.backend.notifications.first.route, '/leads/${lead.id}');
      expect(h.backend.leadSources.single.leadsCount, 1);

      await h.settle();
      expect(h.backend.calls.first.leadId, lead.id);
      expect(h.backend.leads[lead.id]!.hasBeenCalled, isTrue);

      await h.push('/leads/${lead.id}');
      expect(find.byType(LeadSourceChip), findsOneWidget);
      expect(find.text('Form'), findsOneWidget);
    }, location: '/leads');

    appTest('auto-call off: lead created, no call', (h) async {
      final form = h.backend.createLeadSource(LeadSourceKind.form);
      h.backend.setLeadSourceAutoCall(form.id, false);
      final calls = h.backend.calls.length;
      final lead = h.backend.simulateFormEnquiry(
        callAfter: const Duration(milliseconds: 100),
      );
      await h.settle();
      expect(h.backend.leads[lead.id]!.status, LeadStatus.newLead);
      expect(h.backend.calls.length, calls);
      expect(h.backend.notifications.first.body, contains('Auto-call is off'));
    });
  });

  group('LeadSourceChip', () {
    testWidgets('only for form and webhook leads', (tester) async {
      Widget app(String source) => MaterialApp(
        home: Scaffold(body: LeadSourceChip(source: source)),
      );
      await tester.pumpWidget(app('webhook'));
      expect(find.text('Website'), findsOneWidget);
      await tester.pumpWidget(app('Manual entry'));
      expect(find.byType(Text), findsNothing);
    });
    test('labels in all locales', () {
      for (final l in AppLang.values) {
        expect(S(l).leadSourceLabel('form'), isNotEmpty);
        expect(S(l).leadSourceLabel('webhook'), isNotEmpty);
        expect(S(l).leadSourceLabel('CSV Import'), isNull);
      }
    });
  });

  group('ApiLeadSourceRepository', () {
    test('calls the owner APIs and parses the one-time token', () async {
      final requests = <String>[];
      final bodies = <Object?>[];
      final client = ApiClient(_FakeStore(), baseUrl: 'https://api.test');
      final src = {
        'id': 'lsrc_1',
        'kind': 'webhook',
        'slug': 'AbCdEfGhIjKl',
        'url': 'https://api.test/hooks/leads/AbCdEfGhIjKl',
        'auto_call': true,
        'leads_count': 3,
        'created_at': '2026-10-09 01:29:20',
      };
      client.dio.httpClientAdapter = _Adapter((o) async {
        requests.add('${o.method} ${o.path}');
        bodies.add(o.data);
        if (o.method == 'GET') {
          return _json({
            'items': [src],
          });
        }
        if (o.path.endsWith('/revoke')) return _json({'success': true});
        if (o.method == 'PATCH') return _json({...src, 'auto_call': false});
        return _json({...src, 'token': 'cplh_secret'}, 201);
      });
      final repo = ApiLeadSourceRepository(client);

      final list = await repo.list();
      expect(list.single.kind, LeadSourceKind.webhook);
      expect(list.single.leadsCount, 3);
      expect(list.single.token, isNull);
      expect(list.single.createdAt.isUtc, isFalse);
      expect(
        list.single.createdAt.toUtc(),
        DateTime.utc(2026, 10, 9, 1, 29, 20),
      );

      final created = await repo.create(LeadSourceKind.webhook);
      expect(created.token, 'cplh_secret');
      expect(bodies.last, {'kind': 'webhook'});

      final patched = await repo.setAutoCall('lsrc_1', autoCall: false);
      expect(patched.autoCall, isFalse);
      expect(bodies.last, {'auto_call': false});

      await repo.revoke('lsrc_1');
      expect(requests, [
        'GET /lead-sources',
        'POST /lead-sources',
        'PATCH /lead-sources/lsrc_1',
        'POST /lead-sources/lsrc_1/revoke',
      ]);
    });

    test('lead-sources writes refresh screens (mutation scope)', () {
      expect(mutationScope('/lead-sources/lsrc_1/revoke'), 'lead-sources');
    });
  });

  group('MockBackend lead sources', () {
    test('one form per business; webhook token only on create', () {
      final b = MockBackend();
      addTearDown(b.dispose);
      final f1 = b.createLeadSource(LeadSourceKind.form);
      final f2 = b.createLeadSource(LeadSourceKind.form);
      expect(f2.id, f1.id);
      final hook = b.createLeadSource(LeadSourceKind.webhook);
      expect(hook.token, startsWith('cplh_'));
      expect(b.leadSources.firstWhere((x) => x.id == hook.id).token, isNull);
      b.revokeLeadSource(hook.id);
      expect(b.leadSources.map((x) => x.id), [f1.id]);
      expect(() => b.setLeadSourceAutoCall('nope', true), throwsStateError);
    });
  });
}

class _FixedLang extends LanguageController {
  _FixedLang(this.lang);
  final AppLang lang;
  @override
  AppLang? build() => lang;
}

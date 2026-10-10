import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_playbooks.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/templates/templates.dart';
import 'package:callpilot/features/agent/playbook_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_controller.dart';
import 'package:callpilot/features/usage/billing_actions.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _Store extends SecureStore {
  @override
  Future<String?> accessToken() async => 'access';
  @override
  Future<String?> refreshToken() async => 'refresh';
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(o);
  @override
  void close({bool force = false}) {}
}

const _json = {
  'id': 'salon',
  'category': 'salon',
  'language': 'hi',
  'name': 'सैलून और स्पा',
  'business_name': 'Glow',
  'qualifying_questions': ['Q1', 'Q2', 'Q3'],
  'ready_to_buy': {
    'description': 'Books a slot',
    'temperature': 'hot',
    'intents': ['interested'],
    'min_score': 80,
  },
  'objections': [
    {'objection': 'Too costly', 'hint': 'Mention packages'},
  ],
  'followup_templates': {
    'hot': 'Hi {name}, thanks for booking with {business}!',
    'warm': 'Hi {name}, prices from {business}.',
    'callback': 'Hi {name}, {business} will call back.',
    'not_interested': 'Hi {name}, thanks. {business}',
  },
  'callback_timing': {'hint': '11 am–4 pm', 'start_hour': 11, 'end_hour': 16},
};

void main() {
  group('CallPlaybook model', () {
    test('parses GET /playbooks/current', () {
      final p = CallPlaybook.fromJson(_json);
      expect(p.vertical, PlaybookVertical.salon);
      expect(p.category, 'salon');
      expect(p.language, 'hi');
      expect(p.name, 'सैलून और स्पा');
      expect(p.businessName, 'Glow');
      expect(p.qualifyingQuestions, ['Q1', 'Q2', 'Q3']);
      expect(p.readyToBuy, 'Books a slot');
      expect(p.minScore, 80);
      expect(p.objections.single.objection, 'Too costly');
      expect(p.objections.single.hint, 'Mention packages');
      expect(p.followupTemplates.keys, FollowupOutcome.values);
      expect(p.callbackHint, '11 am–4 pm');
      expect(p.callbackStartHour, 11);
      expect(p.callbackEndHour, 16);
    });

    test('tolerates missing and malformed fields', () {
      final p = CallPlaybook.fromJson({
        'id': 'nope',
        'ready_to_buy': 'x',
        'followup_templates': {'hot': 'Hi'},
      });
      expect(p.vertical, PlaybookVertical.general);
      expect(p.category, isNull);
      expect(p.language, 'en');
      expect(p.qualifyingQuestions, isEmpty);
      expect(p.readyToBuy, '');
      expect(p.minScore, 75);
      expect(p.followupTemplates.keys, [FollowupOutcome.hot]);
      expect(p.callbackHint, '');
      expect(p.callbackStartHour, isNull);
    });

    test('preview fills the business and shows a name placeholder', () {
      final p = CallPlaybook.fromJson(_json);
      expect(
        p.preview(FollowupOutcome.hot, namePlaceholder: '[Name]'),
        'Hi [Name], thanks for booking with Glow!',
      );
      final noBiz = CallPlaybook.fromJson({..._json, 'business_name': ' '});
      expect(
        noBiz.preview(FollowupOutcome.warm, namePlaceholder: '[N]'),
        'Hi [N], prices from ….',
      );
      final missing = CallPlaybook.fromJson({'id': 'general'});
      expect(
        missing.preview(FollowupOutcome.callback, namePlaceholder: ''),
        '',
      );
    });

    test('maps every business category to the backend playbook', () {
      expect(
        playbookVerticalFor(BusinessCategory.coaching),
        PlaybookVertical.education,
      );
      expect(
        playbookVerticalFor(BusinessCategory.clinic),
        PlaybookVertical.healthcare,
      );
      expect(
        playbookVerticalFor(BusinessCategory.diagnostic),
        PlaybookVertical.healthcare,
      );
      expect(
        playbookVerticalFor(BusinessCategory.realEstate),
        PlaybookVertical.realEstate,
      );
      expect(
        playbookVerticalFor(BusinessCategory.salon),
        PlaybookVertical.salon,
      );
      expect(
        playbookVerticalFor(BusinessCategory.gym),
        PlaybookVertical.fitness,
      );
      expect(
        playbookVerticalFor(BusinessCategory.restaurant),
        PlaybookVertical.general,
      );
      expect(playbookVerticalFor(null), PlaybookVertical.general);
      for (final v in PlaybookVertical.values) {
        expect(PlaybookVertical.parse(v.wire), v);
      }
      expect(BusinessCategory.parse('gym'), BusinessCategory.gym);
      expect(
        templateFor(BusinessCategory.gym).workflow.id,
        'gym_memberships_v1',
      );
    });

    test('every vertical and outcome has a name in all three languages', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        for (final v in PlaybookVertical.values) {
          expect(s.playbookName(v), isNotEmpty);
          expect(
            s.obPlaybookReady(s.playbookName(v)),
            contains(s.playbookName(v)),
          );
        }
        for (final o in FollowupOutcome.values) {
          expect(s.followupOutcome(o), isNotEmpty);
        }
        expect(s.category(BusinessCategory.gym), isNotEmpty);
        expect(s.data('Weight loss'), isNotEmpty);
      }
      expect(const S(AppLang.hi).playbookTitle, 'आपकी कॉल प्लेबुक');
      expect(const S(AppLang.bn).data('Trainer'), 'ট্রেনার');
    });
  });

  group('playbook repositories', () {
    test('GET /playbooks/current passes the language', () async {
      final client = ApiClient(_Store(), baseUrl: 'https://api.test');
      final queries = <Map<String, dynamic>>[];
      client.dio.httpClientAdapter = _Adapter((o) async {
        expect(o.path, '/playbooks/current');
        queries.add(o.queryParameters);
        return ResponseBody.fromString(
          '{"id":"fitness","name":"Gym & fitness","qualifying_questions":["a"]}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final repo = ApiPlaybookRepository(client);
      final p = await repo.current(lang: 'bn');
      expect(p.vertical, PlaybookVertical.fitness);
      await repo.current();
      expect(queries[0], {'lang': 'bn'});
      expect(queries[1].containsKey('lang'), isFalse);
    });

    test('mock serves the business vertical', () async {
      final b = MockBackend();
      final p = await MockPlaybookRepository(b).current(lang: 'hi');
      expect(p.vertical, PlaybookVertical.education);
      expect(p.qualifyingQuestions, hasLength(5));
      expect(p.businessName, b.business.name);
      final other = mockPlaybookFor(
        b.business.copyWith(category: BusinessCategory.gym),
      );
      expect(other.vertical, PlaybookVertical.fitness);
      expect(other.name, 'Gym & fitness');
      expect(other.qualifyingQuestions, hasLength(4));
      expect(other.followupTemplates, hasLength(4));
      b.dispose();
    });

    test('customise link mails support with the playbook name', () {
      final p = CallPlaybook.fromJson(_json);
      final uri = playbookCustomiseUri(S.en, p);
      expect(uri.scheme, 'mailto');
      expect(
        Uri.decodeComponent(uri.query),
        'subject=Customise my call playbook (सैलून और स्पा)',
      );
    });
  });

  group('PlaybookScreen', () {
    final opened = <Uri>[];
    appTest(
      'Agent tab opens the playbook with questions and follow-ups',
      (h) async {
        final row = find.text('Your call playbook');
        await h.tester.scrollUntilVisible(
          row,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await h.tester.pump();
        expect(find.text('Coaching & education'), findsOneWidget);
        await h.tap(row);
        expect(h.location, '/agent/playbook');
        expect(find.byType(PlaybookScreen), findsOneWidget);
        expect(find.text('Coaching & education playbook'), findsOneWidget);
        expect(
          find.text(
            'Which class or exam is the student preparing for, and for which year?',
          ),
          findsOneWidget,
        );
        expect(find.text('Ready to buy means'), findsOneWidget);
        expect(
          find.text(
            'Such customers are marked hot, with a score of 75 or more.',
          ),
          findsOneWidget,
        );

        final hot = find.byKey(const ValueKey('followup-hot'));
        await h.tester.scrollUntilVisible(
          hot,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        final text = h.tester.widget<Text>(hot).data!;
        expect(text, startsWith('Hi [Name], thanks for speaking with '));
        expect(text, contains(h.backend.business.name));
        expect(find.text('Asked for a call back'), findsOneWidget);

        // No mail app in tests: the owner sees where to write instead.
        final button = find.text('Ask us to customise');
        await h.tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await h.tap(button);
        expect(
          find.textContaining('Couldn’t open your email app'),
          findsOneWidget,
        );
        expect(opened.single.scheme, 'mailto');
        expect(opened.single.query, contains('Coaching'));
      },
      location: '/agent',
      overrides: () => [
        externalUrlLauncherProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return false;
        }),
      ],
    );

    appTest('onboarding confirms the playbook once a type is picked', (
      h,
    ) async {
      await h.go('/onboarding/business-type');
      expect(find.byKey(const ValueKey('playbook-ready')), findsNothing);
      h.container
          .read(onboardingProvider.notifier)
          .selectCategory(BusinessCategory.gym);
      await h.settle();
      expect(
        find.text('We set up the Gym & fitness playbook for you'),
        findsOneWidget,
      );
    }, onboarded: false);
  });
}

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/utils/format.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/home/results_card.dart';
import 'package:callpilot/features/home/week_funnel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

void main() {
  group('results models', () {
    test('ResultsSummary parses current, previous and value', () {
      final r = ResultsSummary.fromJson({
        'range': 'week',
        'enquiries': 12,
        'calls': 30,
        'calls_connected': 18,
        'interested': 7,
        'ready_to_buy': 3,
        'followups_sent': 5,
        'estimated_value_inr': 15000,
        'avg_deal_value_inr': 5000,
        'has_calls': true,
        'previous': {'enquiries': 10, 'ready_to_buy': 1},
      });
      expect(r.range, ResultsRange.week);
      expect(r.current.enquiries, 12);
      expect(r.current.callsConnected, 18);
      expect(r.current.readyToBuy, 3);
      expect(r.current.followUpsSent, 5);
      expect(r.current.estimatedValueInr, 15000);
      expect(r.previous.enquiries, 10);
      expect(r.previous.readyToBuy, 1);
      expect(r.previous.estimatedValueInr, isNull);
      expect(r.avgDealValueInr, 5000);
      expect(r.hasCalls, isTrue);
    });

    test('ResultsSummary tolerates a sparse payload', () {
      final r = ResultsSummary.fromJson({});
      expect(r.range, ResultsRange.week);
      expect(r.current.calls, 0);
      expect(r.avgDealValueInr, isNull);
      expect(r.hasCalls, isFalse);
    });

    test('OwnerTestCallInfo parses', () {
      final i = OwnerTestCallInfo.fromJson({
        'phone': '919830012345',
        'remaining_today': 2,
        'limit': 3,
      });
      expect(i.phone, '919830012345');
      expect(i.remainingToday, 2);
      expect(i.limit, 3);
    });

    test('Business digest and average sale round-trip', () {
      final b = Business.fromJson({
        'id': 'b',
        'name': 'X',
        'category': 'coaching',
      });
      expect(b.digestEnabled, isTrue, reason: 'on by default');
      expect(b.avgDealValueInr, isNull);

      final set = b.copyWith(digestEnabled: false, avgDealValueInr: 4500);
      final json = set.toJson();
      expect(json['digest_enabled'], isFalse);
      expect(json['avg_deal_value_inr'], 4500);
      final back = Business.fromJson(json);
      expect(back.digestEnabled, isFalse);
      expect(back.avgDealValueInr, 4500);

      final cleared = set.copyWith(clearAvgDealValue: true);
      expect(cleared.avgDealValueInr, isNull);
      // Sent as null so the backend clears it (schema is nullable).
      expect(cleared.toJson().containsKey('avg_deal_value_inr'), isTrue);
      expect(cleared.toJson()['digest_enabled'], isFalse);
    });
  });

  group('mock results + owner test call', () {
    test('results value = ready to buy x average sale', () async {
      final b = MockBackend();
      addTearDown(b.dispose);
      final repo = MockDashboardRepository(b);
      final before = await repo.results(ResultsRange.week);
      expect(before.current.estimatedValueInr, isNull);

      b.business = b.business.copyWith(avgDealValueInr: 2000);
      final after = await repo.results(ResultsRange.week);
      expect(after.avgDealValueInr, 2000);
      expect(after.current.estimatedValueInr, after.current.readyToBuy * 2000);
      expect(after.hasCalls, b.calls.isNotEmpty);
    });

    test('owner test call: invalid number, then daily limit', () async {
      final b = MockBackend();
      addTearDown(b.dispose);
      final repo = MockCallRepository(b);
      final info = await repo.ownerTestCallInfo();
      expect(info.remainingToday, MockCallRepository.ownerTestCallLimit);

      await expectLater(
        repo.callOwner('123'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'invalid_phone'),
        ),
      );
      for (var i = MockCallRepository.ownerTestCallLimit - 1; i >= 0; i--) {
        final r = await repo.callOwner('98300 12345');
        expect(r.remainingToday, i);
      }
      await expectLater(
        repo.callOwner('98300 12345'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'test_call_limit'),
        ),
      );
    });
  });

  group('Home results card', () {
    appTest('asks for the average sale value, then shows the estimate', (
      h,
    ) async {
      final results = h.container.read(weekResultsProvider).value!;
      expect(results.hasCalls, isTrue);
      expect(find.byType(WeekFunnelCard), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);

      await h.tapText('Add your average sale value to see what this is worth');
      expect(find.text('Average sale value'), findsWidgets);
      await h.tester.enterText(find.byType(TextField), '5000');
      await h.tapText('Save');

      expect(h.backend.business.avgDealValueInr, 5000);
      final hot = h.container
          .read(weekResultsProvider)
          .value!
          .current
          .readyToBuy;
      // The money figure counts up to its final value.
      await h.settle(10);
      expect(find.text(Fmt.inr(hot * 5000)), findsOneWidget);
      expect(find.text('could come from $hot ready buyers'), findsOneWidget);
    });

    appTest('before any call, Home offers to call the owner', (h) async {
      expect(find.byType(HearYourAiCard), findsOneWidget);
      await h.tapText('Call me now');
      // Prefilled with the owner's number from GET /agent/test-call.
      expect(find.text('+91 98300 12345'), findsOneWidget);
      await h.tap(find.text('Call me now').last);
      expect(
        find.text('Calling you now. Your phone will ring in a few seconds.'),
        findsOneWidget,
      );
      expect(find.textContaining('2 test calls left today'), findsOneWidget);
    }, backend: () => MockBackend()..calls.clear());
  });

  group('Agent settings', () {
    appTest('daily summary switch saves digest_enabled', (h) async {
      expect(h.backend.business.digestEnabled, isTrue);
      await h.tap(find.text('Daily summary at 7 PM'));
      expect(h.backend.business.digestEnabled, isFalse);
    }, location: '/agent');
  });
}

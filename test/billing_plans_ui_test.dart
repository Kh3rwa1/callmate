import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/usage/plan_banner.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Usage repo whose checkout always fails with [error].
class _FailingRepo implements UsageRepository {
  _FailingRepo(this.usage, this.error);
  final Usage usage;
  final Object error;
  @override
  Future<Usage> get() async => usage;
  @override
  Future<String?> checkout({String planId = 'starter'}) async => throw error;
}

Usage _active({
  int included = 1000,
  int used = 0,
  int topup = 0,
  int bonus = 0,
}) => Usage(
  subscription: Subscription(
    planName: 'Starter',
    planId: 'starter',
    includedMinutes: included,
    topupMinutes: topup,
    bonusMinutes: bonus,
    renewsAt: DateTime.utc(2026, 11, 1),
    currentPeriodEnd: DateTime.utc(2026, 11, 1),
    priceInr: 4999,
  ),
  minutesUsed: used,
  callsMade: 1,
);

MockBackend Function() _backendIn(PlanStatus status, {int minutesLeft = 30}) =>
    () => MockBackend()..simulatePlanState(status, minutesLeft: minutesLeft);

Future<void> _scrollTo(AppHarness h, Finder f) async {
  await h.tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await h.tester.pump();
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  group('Catalogue model', () {
    test('parses plans, top-ups, GST and minute balances', () {
      final u = Usage.fromJson({
        'subscription': {
          'plan_id': 'growth',
          'plan_status': 'active',
          'included_minutes': 3000,
          'topup_minutes': 250,
          'bonus_minutes': 100,
          'billing_cycle': 'annual',
          'annual_until': '2027-10-01 00:00:00',
        },
        'minutes_used': 3100,
        'can_buy_topup': true,
        'checkout_plan': {
          'plan_id': 'growth',
          'name': 'Growth',
          'price_inr': 11999,
          'gst_inr': 2160,
          'total_inr': 14159,
          'included_minutes': 3000,
        },
        'plans': [
          {
            'plan_id': 'growth_annual',
            'kind': 'annual',
            'name': 'Growth (annual)',
            'price_inr': 119990,
            'gst_inr': 21598,
            'total_inr': 141588,
            'included_minutes': 3000,
            'months': 12,
          },
        ],
        'topups': [
          {
            'plan_id': 'topup_250',
            'kind': 'topup',
            'price_inr': 1499,
            'gst_inr': 270,
            'total_inr': 1769,
            'included_minutes': 250,
            'months': 0,
          },
        ],
      });
      expect(u.subscription.annual, isTrue);
      expect(u.subscription.annualUntil, isNotNull);
      expect(u.subscription.totalMinutes, 3350);
      // Plan used up, top-up and bonus still callable.
      expect(u.minutesRemaining, 250);
      expect(u.exhausted, isFalse);
      expect(u.canBuyTopup, isTrue);
      expect(u.checkoutPlan.totalInr, 14159);
      expect(u.plans.single.isAnnual, isTrue);
      expect(u.plans.single.basePlanId, 'growth');
      expect(u.topups.single.isTopup, isTrue);

      // An older backend: default plans, no top-ups.
      final legacy = Usage.fromJson({
        'subscription': {'plan_status': 'active', 'included_minutes': 1000},
      });
      expect(legacy.plans, CheckoutPlan.defaultPlans);
      expect(legacy.canBuyTopup, isFalse);
      expect(legacy.checkoutPlan.gstInr, 900);
    });

    test('low-minutes banner offers a top-up on an active plan', () {
      const s = S.en;
      final low = _active(used: 980);
      expect(
        planBannerMessage(s, low),
        'Only 20 calling minutes left this month.',
      );
      expect(planBannerOffersTopup(low), isTrue);
      // Bonus minutes count towards what is left.
      expect(planBannerMessage(s, _active(used: 980, bonus: 500)), isNull);
      expect(planBannerOffersTopup(_active(used: 100)), isFalse);
      final usedUp = _active(used: 1000);
      expect(planBannerMessage(s, usedUp), s.bannerMinutesUsedUp);
      expect(planBannerOffersTopup(usedUp), isTrue);
    });

    test('new strings exist in Hindi and Bengali', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        expect(s.twoMonthsFree, isNotEmpty);
        expect(s.buyMoreMinutes, isNotEmpty);
        expect(s.topupNeedsActivePlan, isNotEmpty);
        expect(s.bannerPaidLow('5'), contains('5'));
      }
      expect(S(AppLang.hi).twoMonthsFree, isNot(S.en.twoMonthsFree));
      expect(S(AppLang.bn).buyMoreMinutes, isNot(S.en.buyMoreMinutes));
    });
  });

  group('Plan picker sheet', () {
    appTest(
      'monthly/yearly toggle, GST breakdown and paying for Growth',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        expect(_inSheet(find.text('Choose a plan')), findsOneWidget);
        expect(_inSheet(find.text('Yearly · 2 months free')), findsOneWidget);
        // Starter preselected: ₹4,999 + ₹900 GST.
        expect(_inSheet(find.text('Pay ₹5,899')), findsOneWidget);
        expect(_inSheet(find.text('GST (18%)')), findsOneWidget);

        await h.tap(find.byKey(const ValueKey('checkout-option-growth')));
        expect(_inSheet(find.text('₹2,160')), findsOneWidget);
        expect(_inSheet(find.text('₹14,159')), findsOneWidget);

        await h.tap(find.text('Yearly · 2 months free'));
        expect(
          find.byKey(const ValueKey('checkout-option-growth_annual')),
          findsOneWidget,
        );
        expect(_inSheet(find.text('₹1,19,990 / year')), findsOneWidget);
        await h.tap(find.text('Pay ₹1,41,588'));

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(S.en.paymentReceived), findsOneWidget);
        expect(h.backend.usage.subscription.planId, 'growth');
        expect(h.backend.usage.subscription.annual, isTrue);
        expect(h.backend.usage.subscription.includedMinutes, 3000);
        await _scrollTo(h, find.text('Yearly plan until'));
        expect(find.text('Yearly plan until'), findsOneWidget);
      },
      location: '/usage',
      backend: _backendIn(PlanStatus.trial, minutesLeft: 4),
    );

    appTest(
      'trial has no Buy more minutes button',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        expect(find.text('Buy more minutes'), findsNothing);
      },
      location: '/usage',
      backend: _backendIn(PlanStatus.trial, minutesLeft: 4),
    );
  });

  group('Top-up sheet', () {
    appTest(
      'buys 1000 extra minutes on an active plan',
      (h) async {
        await _scrollTo(h, find.text('Buy more minutes'));
        await h.tap(find.text('Buy more minutes'));
        expect(
          _inSheet(
            find.text('Extra minutes stay valid until your plan renews.'),
          ),
          findsOneWidget,
        );
        expect(_inSheet(find.text('Pay ₹1,769')), findsOneWidget);
        await h.tap(find.byKey(const ValueKey('checkout-option-topup_1000')));
        await h.tap(find.text('Pay ₹6,489'));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Extra minutes added ✓'), findsOneWidget);
        expect(h.backend.usage.subscription.topupMinutes, 1000);
        expect(h.backend.usage.subscription.includedMinutes, 1000);
        await _scrollTo(h, find.text('Added minutes'));
        expect(find.text('Added minutes'), findsOneWidget);
      },
      location: '/usage',
      backend: _backendIn(PlanStatus.active, minutesLeft: 10),
    );

    appTest(
      'a plan_not_active error is shown inside the sheet',
      (h) async {
        await _scrollTo(h, find.text('Buy more minutes'));
        await h.tap(find.text('Buy more minutes'));
        await h.tap(find.text('Pay ₹1,769'));
        expect(_inSheet(find.text(S.en.topupNeedsActivePlan)), findsOneWidget);
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FailingRepo(
            _active(used: 990),
            const ApiException(
              'Extra minutes can be added to an active plan.',
              statusCode: 409,
              code: 'plan_not_active',
            ),
          ),
        ),
      ],
    );

    appTest('low-minutes banner on Home opens the top-up sheet', (h) async {
      expect(
        find.text('Only 10 calling minutes left this month.'),
        findsOneWidget,
      );
      expect(find.text('Buy minutes'), findsOneWidget);
      await h.tap(find.text('Buy minutes'));
      expect(h.location, '/usage');
      expect(_inSheet(find.text('Buy more minutes')), findsOneWidget);
    }, backend: _backendIn(PlanStatus.active, minutesLeft: 10));
  });
}

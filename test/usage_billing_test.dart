import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/usage/billing_actions.dart';
import 'package:callpilot/features/usage/plan_banner.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Usage repo backed by a fixed [usage]; checkout returns [url] or throws.
class _FakeUsageRepo implements UsageRepository {
  _FakeUsageRepo(this.usage, {this.url, this.error});
  Usage usage;
  final String? url;
  final Object? error;
  int gets = 0;
  int checkouts = 0;

  @override
  Future<Usage> get() async {
    gets++;
    return usage;
  }

  @override
  Future<String?> checkout({String planId = 'starter'}) async {
    checkouts++;
    if (error != null) throw error!;
    return url;
  }
}

Usage _usage(PlanStatus status, {int included = 30, int used = 0}) => Usage(
  subscription: Subscription(
    planName: status == PlanStatus.trial ? 'Free trial' : 'Starter',
    planId: status == PlanStatus.trial ? 'trial' : 'starter',
    status: status,
    includedMinutes: included,
    renewsAt: DateTime.utc(2026, 11, 1),
    currentPeriodEnd: status == PlanStatus.trial
        ? null
        : DateTime.utc(2026, 11, 1),
    priceInr: status == PlanStatus.trial ? 0 : 4999,
  ),
  minutesUsed: used,
  callsMade: 3,
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

void main() {
  group('Usage model', () {
    test('parses plan fields and defaults legacy payloads to active', () {
      final u = Usage.fromJson({
        'subscription': {
          'plan_name': 'Free trial',
          'plan_id': 'trial',
          'plan_status': 'trial',
          'included_minutes': 30,
          'current_period_end': null,
        },
        'minutes_used': 27,
        'checkout_plan': {
          'plan_id': 'starter',
          'name': 'Starter',
          'price_inr': 4999,
          'included_minutes': 1000,
        },
      });
      expect(u.subscription.status, PlanStatus.trial);
      expect(u.subscription.currentPeriodEnd, isNull);
      expect(u.trialLow, isTrue);
      expect(u.checkoutPlan.priceInr, 4999);

      final paid = Usage.fromJson({
        'subscription': {
          'plan_status': 'past_due',
          'current_period_end': '2026-10-09 01:29:20',
        },
      });
      expect(paid.subscription.status, PlanStatus.pastDue);
      expect(paid.subscription.status.blocksCalling, isTrue);
      expect(
        paid.subscription.currentPeriodEnd!.toUtc(),
        DateTime.utc(2026, 10, 9, 1, 29, 20),
      );

      final legacy = Usage.fromJson({
        'subscription': {'plan_name': 'Founding Plan'},
      });
      expect(legacy.subscription.status, PlanStatus.active);
    });

    test('banner message per state', () {
      const s = S.en;
      expect(planBannerMessage(s, _usage(PlanStatus.trial, used: 0)), isNull);
      expect(
        planBannerMessage(s, _usage(PlanStatus.trial, used: 26)),
        'Only 4 free trial minutes left.',
      );
      expect(
        planBannerMessage(s, _usage(PlanStatus.trial, used: 30)),
        s.bannerTrialUsedUp,
      );
      expect(
        planBannerMessage(s, _usage(PlanStatus.pastDue, included: 1000)),
        s.bannerPastDue,
      );
      expect(
        planBannerMessage(s, _usage(PlanStatus.active, included: 1000)),
        isNull,
      );
      expect(
        planBannerMessage(
          s,
          _usage(PlanStatus.active, included: 1000, used: 1000),
        ),
        s.bannerMinutesUsedUp,
      );
    });
  });

  group('UsageScreen states', () {
    appTest(
      'trial shows Free trial status, minutes left and Upgrade',
      (h) async {
        expect(find.text('Free trial'), findsNWidgets(2)); // name + chip
        expect(find.text('4'), findsOneWidget);
        expect(find.text('Renews on'), findsNothing);
        await _scrollTo(h, find.text('Upgrade'));
        expect(find.text('Upgrade'), findsOneWidget);
        expect(
          find.text(
            'Free trial minutes do not renew. Upgrade to keep calling.',
          ),
          findsOneWidget,
        );
      },
      location: '/usage',
      backend: _backendIn(PlanStatus.trial, minutesLeft: 4),
    );

    appTest(
      'past due shows Payment due and Renew plan',
      (h) async {
        expect(find.text('Payment due'), findsOneWidget);
        expect(find.text('Payment was due on'), findsOneWidget);
        await _scrollTo(h, find.text('Renew plan'));
        expect(find.text('Renew plan'), findsOneWidget);
      },
      location: '/usage',
      backend: _backendIn(PlanStatus.pastDue, minutesLeft: 0),
    );

    late _FakeUsageRepo opened;
    final launched = <Uri>[];
    appTest(
      'Upgrade opens the payment page externally and refreshes on return',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        expect(opened.checkouts, 1);
        expect(launched.single.toString(), 'https://rzp.io/i/abc');

        // Paid in the browser; the webhook activated the plan.
        opened.usage = _usage(PlanStatus.active, included: 1000);
        final before = opened.gets;
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.hidden,
        );
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.hidden,
        );
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        h.tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await h.settle();
        expect(opened.gets, greaterThan(before));
        expect(find.text('Active'), findsOneWidget);
        await h.tester.pump(const Duration(seconds: 5));
      },
      location: '/usage',
      overrides: () {
        opened = _FakeUsageRepo(
          _usage(PlanStatus.trial, used: 30),
          url: 'https://rzp.io/i/abc',
        );
        launched.clear();
        return [
          usageRepoProvider.overrideWithValue(opened),
          externalUrlLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ];
      },
    );

    appTest(
      'billing_not_configured falls back to the contact message',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        expect(
          find.text(
            'Our team will reach out on WhatsApp to upgrade your plan.',
          ),
          findsOneWidget,
        );
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(
            _usage(PlanStatus.trial, used: 30),
            error: const ApiException(
              'Online payments are not set up yet.',
              statusCode: 503,
              code: 'billing_not_configured',
            ),
          ),
        ),
      ],
    );

    appTest(
      'a failed launch shows an error',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        expect(
          find.text("Couldn't open the payment page. Please try again."),
          findsOneWidget,
        );
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(_usage(PlanStatus.trial), url: 'https://rzp.io/i/x'),
        ),
        externalUrlLauncherProvider.overrideWithValue((_) async => false),
      ],
    );
  });

  group('Home plan banner', () {
    appTest('past due banner links to Plan & usage', (h) async {
      expect(find.text(S.en.bannerPastDue), findsOneWidget);
      await h.tap(find.text(S.en.bannerPastDue));
      expect(h.location, '/usage');
    }, backend: _backendIn(PlanStatus.pastDue, minutesLeft: 0));

    appTest('trial running low shows minutes left', (h) async {
      expect(find.text('Only 4 free trial minutes left.'), findsOneWidget);
    }, backend: _backendIn(PlanStatus.trial, minutesLeft: 4));

    appTest('healthy paid plan shows no banner', (h) async {
      expect(find.byKey(const ValueKey('plan-banner')), findsNothing);
    });
  });
}

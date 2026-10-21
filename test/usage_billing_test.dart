import 'package:callpilot/core/config/app_env.dart';
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

/// Usage repo backed by a fixed [usage]; checkout returns [url] or [upi], or
/// throws [error]. UTR submissions are recorded and fail with [utrError].
class _FakeUsageRepo implements UsageRepository {
  _FakeUsageRepo(this.usage, {this.url, this.upi, this.error, this.utrError});
  Usage usage;
  final String? url;
  final UpiCheckout? upi;
  final Object? error;
  final Object? utrError;
  int gets = 0;
  int checkouts = 0;
  String? lastPlanId;
  final utrs = <(String, String)>[];

  @override
  Future<Usage> get() async {
    gets++;
    return usage;
  }

  @override
  Future<CheckoutStart> checkout({String planId = 'starter'}) async {
    checkouts++;
    lastPlanId = planId;
    if (error != null) throw error!;
    return CheckoutStart(url: url, upi: upi);
  }

  @override
  Future<void> submitUpiUtr({
    required String orderId,
    required String utr,
  }) async {
    utrs.add((orderId, utr));
    if (utrError != null) throw utrError!;
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
        expect(find.text('Free trial'), findsOneWidget); // said once, not twice
        expect(find.text('4'), findsOneWidget);
        expect(find.text('Plan ends on'), findsNothing);
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
        expect(opened.checkouts, 0); // the plan picker opens first
        await h.tap(find.text('Pay ₹5,899'));
        expect(opened.checkouts, 1);
        expect(opened.lastPlanId, 'starter');
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

    final emailed = <Uri>[];
    appTest(
      'billing_not_configured offers an upgrade email instead of paying',
      (h) async {
        emailed.clear();
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        await h.tap(find.text('Pay ₹5,899'));
        // Shown inside the sheet (a snackbar would sit behind it).
        final inSheet = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(
            'Online payment isn’t available yet. Email us and we’ll upgrade your plan.',
          ),
        );
        expect(inSheet, findsOneWidget);
        expect(find.text('Pay ₹5,899'), findsNothing);
        await h.tap(find.text('Email us'));
        expect(emailed, hasLength(1));
        expect(emailed.single.scheme, 'mailto');
        expect(emailed.single.path, AppEnv.supportEmail);
        expect(
          emailed.single.queryParameters['subject'],
          'Upgrade my CallPilot plan to Starter',
        );
        expect(emailed.single.queryParameters['body'], contains('₹5,899'));
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
        externalUrlLauncherProvider.overrideWithValue((uri) async {
          emailed.add(uri);
          return true;
        }),
      ],
    );

    appTest(
      'a failed launch shows an error',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        await h.tap(find.text('Pay ₹5,899'));
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(
              "Couldn't open the payment page. Please try again.",
            ),
          ),
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

  group('UPI payments', () {
    const upi = UpiCheckout(
      orderId: 'upi_ab12cd34ef56',
      uri:
          'upi://pay?pa=tumdah%40okhdfcbank&pn=Tumdah&am=5899.00&cu=INR&tn=CallPilot%20CPK7Q2M9X',
      vpa: 'tumdah@okhdfcbank',
      payeeName: 'Tumdah',
      reference: 'CPK7Q2M9X',
      amountInr: 5899,
    );

    test('checkout and usage payloads parse the UPI fields', () {
      final start = CheckoutStart.fromJson({
        'id': 'upi_ab12cd34ef56',
        'total_inr': 5899,
        'upi': {
          'order_id': 'upi_ab12cd34ef56',
          'uri': upi.uri,
          'vpa': 'tumdah@okhdfcbank',
          'payee_name': 'Tumdah',
          'reference': 'CPK7Q2M9X',
          'amount_inr': 5899,
        },
      });
      expect(start.url, isNull);
      expect(start.upi?.orderId, 'upi_ab12cd34ef56');
      expect(start.upi?.vpa, 'tumdah@okhdfcbank');
      expect(start.upi?.amountInr, 5899);
      expect(CheckoutStart.fromJson({'url': 'https://rzp.io/i/x'}).upi, isNull);

      final u = Usage.fromJson({
        'subscription': {'plan_status': 'trial'},
        'pending_payment': {
          'order_id': 'upi_ab12cd34ef56',
          'reference': 'CPK7Q2M9X',
          'plan_id': 'starter',
          'plan_name': 'Starter',
          'total_inr': 5899,
          'status': 'rejected',
          'submitted_at': '2026-10-21 02:00:00',
        },
      });
      expect(u.pendingPayment?.reference, 'CPK7Q2M9X');
      expect(u.pendingPayment?.rejected, isTrue);
      expect(Usage.fromJson({'pending_payment': null}).pendingPayment, isNull);
    });

    test('UTRs are 12 digits, spaces and dashes ignored', () {
      expect(normalizeUtr('123456789012'), '123456789012');
      expect(normalizeUtr(' 1234 5678-9012 '), '123456789012');
      expect(normalizeUtr('12345678901'), isNull);
      expect(normalizeUtr('1234567890123'), isNull);
      expect(normalizeUtr('12345678901a'), isNull);
    });

    test('a reported payment replaces the upgrade banner', () {
      const s = S.en;
      final waiting = Usage(
        subscription: _usage(PlanStatus.trial, used: 30).subscription,
        minutesUsed: 30,
        callsMade: 0,
        pendingPayment: const PendingPayment(
          orderId: 'upi_1',
          reference: 'CPK7Q2M9X',
          planName: 'Starter',
          totalInr: 5899,
        ),
      );
      expect(
        planBannerMessage(s, waiting),
        'We’re confirming your payment of ₹5,899 (ref CPK7Q2M9X).',
      );
    });

    late _FakeUsageRepo repo;
    final launched = <Uri>[];
    appTest(
      'pay by UPI, then send the UTR',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        await h.tap(find.text('Pay ₹5,899'));
        expect(find.text('Pay ₹5,899 by UPI'), findsOneWidget);
        expect(find.byKey(const Key('upi-qr')), findsOneWidget);
        expect(find.text('tumdah@okhdfcbank'), findsOneWidget);
        expect(find.textContaining('CallPilot CPK7Q2M9X'), findsOneWidget);

        await h.tap(find.text('Pay with a UPI app'));
        expect(launched.single.toString(), upi.uri);

        await h.tester.enterText(find.byKey(const Key('upi-utr')), '12345');
        await h.tap(find.text('I’ve paid, send UTR'));
        expect(
          find.text('Enter the 12-digit UTR from your UPI app.'),
          findsOneWidget,
        );
        expect(repo.utrs, isEmpty);

        await h.tester.enterText(
          find.byKey(const Key('upi-utr')),
          '1234 5678 9012',
        );
        await h.tap(find.text('I’ve paid, send UTR'));
        expect(repo.utrs.single, ('upi_ab12cd34ef56', '123456789012'));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(S.en.upiSubmitted), findsOneWidget);
      },
      location: '/usage',
      overrides: () {
        repo = _FakeUsageRepo(_usage(PlanStatus.trial, used: 30), upi: upi);
        launched.clear();
        return [
          usageRepoProvider.overrideWithValue(repo),
          externalUrlLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ];
      },
    );

    appTest(
      'a UTR already used shows inside the sheet',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        await h.tap(find.text('Pay ₹5,899'));
        await h.tester.enterText(
          find.byKey(const Key('upi-utr')),
          '123456789012',
        );
        await h.tap(find.text('I’ve paid, send UTR'));
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(S.en.utrUsed),
          ),
          findsOneWidget,
        );
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(
            _usage(PlanStatus.trial, used: 30),
            upi: upi,
            utrError: const ApiException(
              'That UTR was already used.',
              statusCode: 409,
              code: 'utr_used',
            ),
          ),
        ),
      ],
    );

    appTest(
      'a UPI app that fails to open points to the QR and UPI ID',
      (h) async {
        await _scrollTo(h, find.text('Upgrade'));
        await h.tap(find.text('Upgrade'));
        await h.tap(find.text('Pay ₹5,899'));
        await h.tap(find.text('Pay with a UPI app'));
        expect(find.text(S.en.upiAppFailed(upi.vpa)), findsOneWidget);
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(_usage(PlanStatus.trial, used: 30), upi: upi),
        ),
        externalUrlLauncherProvider.overrideWithValue((_) async => false),
      ],
    );

    Usage withPending({required bool rejected}) => Usage(
      subscription: _usage(PlanStatus.trial, used: 30).subscription,
      minutesUsed: 30,
      callsMade: 3,
      pendingPayment: PendingPayment(
        orderId: 'upi_1',
        reference: 'CPK7Q2M9X',
        planName: 'Starter',
        totalInr: 5899,
        rejected: rejected,
      ),
    );

    appTest(
      'Plan & usage says a reported payment is being confirmed',
      (h) async {
        expect(find.byKey(const ValueKey('pending-payment')), findsOneWidget);
        expect(
          find.text('We’re confirming your payment of ₹5,899 (ref CPK7Q2M9X).'),
          findsOneWidget,
        );
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(withPending(rejected: false)),
        ),
      ],
    );

    final mailed = <Uri>[];
    appTest(
      'a payment support couldn’t find offers an email',
      (h) async {
        mailed.clear();
        expect(
          find.text('We couldn’t find your payment (ref CPK7Q2M9X). Email us.'),
          findsOneWidget,
        );
        await h.tap(
          find.descendant(
            of: find.byKey(const ValueKey('pending-payment')),
            matching: find.text('Email us'),
          ),
        );
        expect(mailed.single.scheme, 'mailto');
        expect(mailed.single.path, AppEnv.supportEmail);
        expect(
          mailed.single.queryParameters['subject'],
          'CallPilot payment not found (CPK7Q2M9X)',
        );
      },
      location: '/usage',
      overrides: () => [
        usageRepoProvider.overrideWithValue(
          _FakeUsageRepo(withPending(rejected: true)),
        ),
        externalUrlLauncherProvider.overrideWithValue((uri) async {
          mailed.add(uri);
          return true;
        }),
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

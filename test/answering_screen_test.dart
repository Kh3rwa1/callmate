import 'package:callpilot/core/utils/call_forwarding.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/usage/billing_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

List<String> _codes(AnswerMode m, ForwardingNetwork n) =>
    forwardingSteps(m, n, '+917971440001').map((s) => s.code).toList();

void main() {
  group('forwarding codes', () {
    test('standard (Airtel, Vi, BSNL) codes take +91', () {
      expect(_codes(AnswerMode.ai, ForwardingNetwork.gsm), [
        '**21*+917971440001#',
      ]);
      expect(_codes(AnswerMode.missed, ForwardingNetwork.gsm), [
        '##002#',
        '**004*+917971440001#',
      ]);
      expect(_codes(AnswerMode.owner, ForwardingNetwork.gsm), ['##002#']);
    });

    test('Jio has its own codes and takes 10 digits', () {
      expect(_codes(AnswerMode.ai, ForwardingNetwork.jio), [
        '*401*7971440001#',
      ]);
      expect(_codes(AnswerMode.missed, ForwardingNetwork.jio), [
        '##002#',
        '*403*7971440001#',
        '*405*7971440001#',
        '*409*7971440001#',
      ]);
      expect(_codes(AnswerMode.owner, ForwardingNetwork.jio), ['##002#']);
    });

    test('the dialer keeps # only when percent-encoded', () {
      expect(
        Uri(scheme: 'tel', path: '**21*+917971440001#').toString(),
        'tel:**21*+917971440001%23',
      );
    });

    test('models', () {
      final on = AnsweringInfo.fromJson({
        'available': true,
        'enabled': true,
        'phone': '+917971440001',
        'mode': 'all',
      });
      expect(on.mode, AnswerMode.ai);
      expect(
        AnsweringInfo.fromJson({'enabled': true, 'mode': 'missed'}).mode,
        AnswerMode.missed,
      );
      expect(AnsweringInfo.fromJson({'enabled': false}).mode, AnswerMode.owner);
      expect(
        Call.fromJson({'id': 'c', 'direction': 'inbound'}).inbound,
        isTrue,
      );
      expect(Call.fromJson({'id': 'c'}).inbound, isFalse);
    });
  });

  /// A Growth business that already rented its number (demo).
  MockBackend withNumber() {
    final b = MockBackend()..simulatePlanPayment(planId: 'growth');
    b.businessNumber = '+917971440001';
    return b;
  }

  final dialled = <String>[];
  appTest(
    'choosing who answers shows the line and the codes for the network',
    (h) async {
      // Settings row on the Agent tab says who answers today.
      await h.tester.scrollUntilVisible(
        find.byKey(const Key('agent-answering')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await h.settle();
      await h.tap(find.byKey(const Key('agent-answering')));
      expect(h.location, '/agent/answering');

      // Every call → the AI.
      await h.tap(find.byKey(const Key('answer-mode-ai')));
      expect(find.byKey(const Key('answering-line')), findsOneWidget);
      expect(find.text('+91 79714 40001'), findsOneWidget);
      await h.tap(find.byKey(const Key('network-jio')));
      await h.tap(find.byKey(const Key('forward-step-1')));
      expect(dialled.last, 'tel:*401*7971440001%23');

      // Missed calls only, on Airtel: clear, then one code.
      await h.tap(find.byKey(const Key('answer-mode-missed')));
      await h.tap(find.byKey(const Key('network-gsm')));
      await h.tap(find.byKey(const Key('forward-step-1')));
      await h.tap(find.byKey(const Key('forward-step-2')));
      expect(dialled.sublist(dialled.length - 2), [
        'tel:%23%23002%23',
        'tel:**004*+917971440001%23',
      ]);
      expect(find.byKey(const Key('forward-step-3')), findsNothing);

      // Only me: one step that stops forwarding; the line stays.
      await h.tap(find.byKey(const Key('answer-mode-owner')));
      expect(find.byKey(const Key('forward-step-2')), findsNothing);
      expect(find.text('Clear old call forwarding'), findsOneWidget);
      expect(find.byKey(const Key('answering-line')), findsOneWidget);
    },
    location: '/agent',
    backend: withNumber,
    overrides: () => [
      externalUrlLauncherProvider.overrideWithValue((uri) async {
        dialled.add(uri.toString());
        return true;
      }),
    ],
  );

  appTest('without a business number, who answers asks to get one first', (
    h,
  ) async {
    expect(find.byKey(const Key('answering-needs-number')), findsOneWidget);
    expect(find.byKey(const Key('answer-mode-ai')), findsNothing);
    await h.tapText('Get your business number');
    expect(h.location, '/agent/number');
  }, location: '/agent/answering');

  group('business number', () {
    appTest('Starter: explains it and opens the plans on Growth, highlighted', (
      h,
    ) async {
      expect(find.text('One number for your business'), findsOneWidget);
      await h.tap(find.byKey(const Key('number-upgrade')));
      expect(find.text('Choose a plan'), findsOneWidget);
      // Growth is preselected and says what sets it apart.
      expect(find.text('Pay ₹14,159'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-number-growth')), findsOneWidget);
      expect(find.text('Your own business number'), findsOneWidget);
      expect(find.text('Calls from shared CallPilot numbers'), findsOneWidget);
    }, location: '/agent/number');

    appTest(
      'Growth: pick a specific number once, then it is the business number',
      (h) async {
        expect(find.text('Pick your number'), findsOneWidget);
        // Nothing picked yet: can't rent.
        final rent = find.byKey(const Key('rent-number'));
        expect(h.tester.widget<FilledButton>(rent).onPressed, isNull);
        await h.tap(find.byKey(const Key('number-option-+917971440003')));
        await h.tap(rent);
        expect(
          find.text('Make +91 79714 40003 your business number?'),
          findsOneWidget,
        );
        await h.tap(find.byKey(const Key('rent-number-confirm')));
        expect(h.backend.businessNumber, '+917971440003');
        expect(find.byKey(const Key('business-number')), findsOneWidget);
        expect(find.text('+91 79714 40003'), findsOneWidget);
        expect(find.text('Pick your number'), findsNothing);
        // Who answers now works on this number.
        await h.tapText('Who answers my calls');
        expect(find.byKey(const Key('answer-mode-ai')), findsOneWidget);
      },
      location: '/agent/number',
      backend: () => MockBackend()..simulatePlanPayment(planId: 'growth'),
    );

    appTest(
      'plan lapsed: the number is on hold, with how to get calls back',
      (h) async {
        expect(find.text('+91 79714 40001'), findsOneWidget);
        expect(find.text('On hold'), findsOneWidget);
        expect(find.byKey(const Key('number-held-forwarding')), findsOneWidget);
        expect(find.text('Renew Growth to keep your number'), findsOneWidget);
        // Who answers can't forward to a held number.
        await h.go('/agent/answering');
        expect(find.byKey(const Key('answering-needs-number')), findsOneWidget);
      },
      location: '/agent/number',
      backend: () => withNumber()..simulatePlanState(PlanStatus.pastDue),
    );
  });

  appTest('a call the AI answered reads "Called you"', (h) async {
    final c = h.backend.simulateCall(LeadTemperature.hot, inbound: true);
    await h.go('/calls');
    expect(find.textContaining('Called you ·'), findsWidgets);
    await h.push('/calls/${c.id}/result');
    expect(
      find.textContaining('They called, your AI answered ·'),
      findsOneWidget,
    );
  });
}

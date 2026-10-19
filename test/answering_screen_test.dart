import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/utils/call_forwarding.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/usage/billing_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// The pool is used up: turning answering on fails.
class _NoNumbers extends MockCallRepository {
  _NoNumbers(super.b);
  @override
  Future<AnsweringInfo> setAnswering(AnswerMode mode) async =>
      throw const ApiException(
        'No answering numbers are free right now.',
        statusCode: 503,
        code: 'no_numbers',
      );
}

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
      expect(
        find.descendant(
          of: find.byKey(const Key('agent-answering')),
          matching: find.text('Only me'),
        ),
        findsOneWidget,
      );
      await h.tap(find.byKey(const Key('agent-answering')));
      expect(h.location, '/agent/answering');
      expect(find.byKey(const Key('answering-line')), findsNothing);

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
    overrides: () => [
      externalUrlLauncherProvider.overrideWithValue((uri) async {
        dialled.add(uri.toString());
        return true;
      }),
    ],
  );

  appTest(
    'no free numbers: says so instead of a generic error',
    (h) async {
      await h.tap(find.byKey(const Key('answer-mode-ai')));
      expect(
        find.text('No answering numbers are free right now. Try again later.'),
        findsOneWidget,
      );
    },
    location: '/agent/answering',
    overrides: () => [
      callRepoProvider.overrideWith(
        (ref) => _NoNumbers(ref.watch(mockBackendProvider)),
      ),
    ],
  );

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

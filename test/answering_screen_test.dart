import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/agent/answering_screen.dart';
import 'package:callpilot/features/usage/billing_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// The pool is used up: turning answering on fails.
class _NoNumbers extends MockCallRepository {
  _NoNumbers(super.b);
  @override
  Future<AnsweringInfo> setAnswering(bool enabled) async =>
      throw const ApiException(
        'No answering numbers are free right now.',
        statusCode: 503,
        code: 'no_numbers',
      );
}

void main() {
  test('forwarding codes and the inbound flag', () {
    expect(ForwardingCodes.noAnswer('+917971440001'), '**61*+917971440001#');
    expect(ForwardingCodes.busy('+917971440001'), '**67*+917971440001#');
    expect(ForwardingCodes.unreachable('+917971440001'), '**62*+917971440001#');
    // The dialer only keeps the trailing # when it is percent-encoded.
    expect(
      Uri(
        scheme: 'tel',
        path: ForwardingCodes.noAnswer('+917971440001'),
      ).toString(),
      'tel:**61*+917971440001%23',
    );
    expect(
      AnsweringInfo.fromJson({
        'available': true,
        'enabled': true,
        'phone': '+917971440001',
      }).phone,
      '+917971440001',
    );
    expect(Call.fromJson({'id': 'c', 'direction': 'inbound'}).inbound, isTrue);
    expect(Call.fromJson({'id': 'c'}).inbound, isFalse);
  });

  final dialled = <Uri>[];
  appTest(
    'turning it on shows the AI line and opens the dialer with each code',
    (h) async {
      expect(find.byKey(const Key('agent-answering')), findsOneWidget);
      await h.tap(find.byKey(const Key('agent-answering')));
      expect(h.location, '/agent/answering');
      expect(find.byKey(const Key('answering-line')), findsNothing);

      await h.tap(find.byKey(const Key('answering-switch')));
      expect(find.byKey(const Key('answering-line')), findsOneWidget);
      expect(find.text('+91 79714 40001'), findsOneWidget);

      await h.tapText('When I don\'t pick up');
      await h.tapText('When I\'m on another call');
      await h.tapText('Stop sending calls');
      expect(dialled.map((u) => u.toString()), [
        'tel:**61*+917971440001%23',
        'tel:**67*+917971440001%23',
        'tel:%23%23002%23',
      ]);

      // Off again: the number stays, the switch is off.
      await h.tap(find.byKey(const Key('answering-switch')));
      final sw = h.tester.widget<SwitchListTile>(
        find.byKey(const Key('answering-switch')),
      );
      expect(sw.value, isFalse);
      expect(find.byKey(const Key('answering-line')), findsOneWidget);
    },
    location: '/agent',
    overrides: () => [
      externalUrlLauncherProvider.overrideWithValue((uri) async {
        dialled.add(uri);
        return true;
      }),
    ],
  );

  appTest(
    'no free numbers: says so instead of a generic error',
    (h) async {
      await h.tap(find.byKey(const Key('answering-switch')));
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

import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/datasources/mock/mock_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Fixes from testing on a phone (staging, new account, 9 AM).

/// The backend refuses the call outside calling hours.
class _OutsideHours extends MockCallRepository {
  _OutsideHours(super.b);
  @override
  Future<Call> triggerCall(String leadId, {bool consentAttested = false}) =>
      throw const ApiException(
        'This lead can only be called during calling hours.',
        statusCode: 409,
        code: 'outside_hours',
      );
}

MockBackend _newOwner() => MockBackend()..resetToNewAccount();

void main() {
  appTest(
    'a new account\'s Messages says nothing to send yet, not "All sent"',
    (h) async {
      expect(find.text('Nothing to send yet.'), findsOneWidget);
      expect(find.text('All sent. Nice work.'), findsNothing);
    },
    location: '/followups',
    backend: _newOwner,
  );

  appTest(
    'Home "Add customers" opens the add screen, so contacts can be skipped',
    (h) async {
      await h.tap(find.byKey(const Key('hero-action')));
      expect(h.location, '/leads/import');
      expect(find.text('Or type one customer'), findsOneWidget);
    },
    backend: _newOwner,
  );

  appTest(
    'an AI call outside calling hours says when calls are allowed',
    (h) async {
      final lead = h.backend.leads.values.first;
      h.backend.leads[lead.id] = Lead.fromJson({
        ...lead.toJson(),
        'consent': 'explicit_opt_in',
      });
      await h.push('/leads/${lead.id}');
      await h.tap(find.byTooltip('AI Call'));
      await h.tapText('AI call by ${h.backend.agent.name}');
      expect(
        find.text(
          '${h.backend.agent.name} can call customers between 10 AM and 7 PM.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('This lead'), findsNothing);
    },
    overrides: () => [
      callRepoProvider.overrideWith(
        (ref) => _OutsideHours(ref.watch(mockBackendProvider)),
      ),
    ],
  );
}

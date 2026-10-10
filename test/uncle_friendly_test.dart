import 'package:callpilot/core/config/app_env.dart';
import 'package:callpilot/core/settings.dart';
import 'package:callpilot/core/utils/calling_hours.dart';
import 'package:callpilot/core/widgets/settings_sheets.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/agent/agent_screen.dart';
import 'package:callpilot/features/agent/owner_test_call_sheet.dart';
import 'package:callpilot/features/home/getting_started.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/leads/leads_screen.dart';
import 'package:callpilot/features/onboarding/onboarding_screens.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

MockBackend _newOwner() => MockBackend()..resetToNewAccount();

void main() {
  group('GettingStarted.from', () {
    test('nothing done for a brand-new owner', () {
      final g = GettingStarted.from(
        leads: 0,
        heardAi: false,
        hasCalls: false,
        leadSources: 0,
      );
      expect(g.done, 0);
      expect(g.allDone, isFalse);
    });

    test('ticks each item from real data', () {
      final g = GettingStarted.from(
        leads: 3,
        heardAi: false,
        hasCalls: true,
        leadSources: 1,
      );
      expect(g.hasCustomers, isTrue);
      expect(g.heardAi, isTrue, reason: 'a real call counts as hearing it');
      expect(g.formShared, isTrue);
      expect(g.allDone, isTrue);
      expect(
        GettingStarted.from(
          leads: 0,
          heardAi: true,
          hasCalls: false,
          leadSources: 0,
        ).done,
        1,
      );
    });
  });

  group('Getting started card', () {
    appTest('shows for a new owner, one tap per step', (h) async {
      expect(find.byKey(const Key('getting-started')), findsOneWidget);
      expect(find.text('0 of 3 done'), findsOneWidget);
      await h.tap(find.byKey(const Key('getting-started-1')));
      expect(h.location, '/leads/contacts');
      await h.go('/home');
      await h.tap(find.byKey(const Key('getting-started-3')));
      expect(h.location, '/leads/auto');
      await h.go('/home');
      await h.tap(find.byKey(const Key('getting-started-2')));
      expect(find.text('Call me now'), findsWidgets);
    }, backend: _newOwner);

    appTest('ticks items as data arrives and can be hidden', (h) async {
      await h.prefs.setHeardAi(true);
      h.container.invalidate(heardAiProvider);
      await h.settle();
      expect(find.text('1 of 3 done'), findsOneWidget);
      await h.tap(find.byKey(const Key('getting-started-hide')));
      expect(find.byKey(const Key('getting-started')), findsNothing);
      expect(h.prefs.checklistDismissed, isTrue);
    }, backend: _newOwner);

    appTest('hidden once everything is done', (h) async {
      // The demo account has customers, calls and an enquiry form.
      expect(h.backend.leads, isNotEmpty);
      expect(h.backend.calls, isNotEmpty);
      if (h.backend.leadSources.isEmpty) {
        expect(find.byKey(const Key('getting-started')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('getting-started')), findsNothing);
      }
    });
  });

  group('Help', () {
    test('video link per language, hidden when unset', () {
      expect(AppEnv.helpVideoUrl('en', en: '', hi: '', bn: ''), isNull);
      expect(
        AppEnv.helpVideoUrl('hi', en: 'https://e', hi: ' https://h ', bn: ''),
        'https://h',
      );
      expect(
        AppEnv.helpVideoUrl('bn', en: 'https://e', hi: '', bn: ''),
        isNull,
      );
      expect(AppEnv.helpVideoUrl('en', en: 'https://e'), 'https://e');
    });

    test('this build offers email only (no video configured)', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        final options = helpOptions(s);
        expect(options.map((o) => o.$1), [s.helpEmail]);
        expect(options.single.$4.scheme, 'mailto');
        expect(options.single.$4.path, AppEnv.supportEmail);
      }
    });

    appTest('Help on the Home top bar opens the help sheet', (h) async {
      await h.tap(find.byKey(const Key('home-help')));
      expect(find.text('Email us'), findsOneWidget);
      expect(find.text('Watch 1-minute video'), findsNothing);
    });

    appTest('bell and callbacks are on Home with words', (h) async {
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      await h.tap(find.byKey(const Key('home-alerts')));
      expect(h.location, '/notifications');
    });
  });

  group('Text size', () {
    test('parses and multiplies the phone scale, capped at 2x', () {
      expect(TextSize.parse(null), TextSize.normal);
      expect(TextSize.parse('large'), TextSize.large);
      expect(TextSize.parse('xlarge'), TextSize.extraLarge);
      expect(TextSize.extraLarge.wire, 'xlarge');
      expect(TextSize.normal.wire, isNull);
      double f(double sys, TextSize t) =>
          appTextScaler(TextScaler.linear(sys), t).scale(10) / 10;
      expect(f(1, TextSize.normal), 1);
      expect(f(1, TextSize.large), closeTo(1.2, 1e-9));
      expect(f(1.3, TextSize.extraLarge), closeTo(1.82, 1e-9));
      expect(f(1.8, TextSize.extraLarge), kMaxTextScale);
      expect(f(0.5, TextSize.normal), kMinTextScale);
    });
  });

  group('Customers', () {
    appTest('auto leads is a labelled card', (h) async {
      expect(find.text('Get new customers automatically'), findsWidgets);
      await h.tap(find.byKey(const Key('leads-get-automatically')));
      expect(h.location, '/leads/auto');
    }, location: '/leads');
  });

  group('Calling hours', () {
    test('India time window, clamped to TRAI', () {
      // 08:30 UTC = 14:00 IST.
      expect(isIndiaCallingHour(DateTime.utc(2026, 1, 1, 8, 30)), isTrue);
      // 14:00 UTC = 19:30 IST: outside the default 10–19 window.
      expect(isIndiaCallingHour(DateTime.utc(2026, 1, 1, 14)), isFalse);
      expect(
        isIndiaCallingHour(DateTime.utc(2026, 1, 1, 14), start: 9, end: 23),
        isTrue,
        reason: 'end clamps to 21',
      );
      expect(
        isIndiaCallingHour(DateTime.utc(2026, 1, 1, 16), start: 9, end: 23),
        isFalse,
      );
    });

    appTest(
      'the sheet offers the in-app test outside hours',
      (h) async {
        await h.tap(find.byKey(const Key('getting-started-2')));
        expect(find.byKey(const Key('outside-hours')), findsOneWidget);
        await h.tap(find.textContaining('Talk in-app with'));
        expect(h.location, '/voice-test');
      },
      backend: _newOwner,
      overrides: () => [
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1, 18)),
      ],
    );
  });

  group('At text size 2.0 nothing overflows', () {
    Future<void> big(AppHarness h) async {
      h.tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(h.tester.platformDispatcher.clearTextScaleFactorTestValue);
      await h.settle();
    }

    appTest('Home', (h) async {
      await big(h);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('getting-started')), findsOneWidget);
      final ctx = h.tester.element(find.byType(HomeScreen));
      expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(20, 0.01));
    }, backend: _newOwner);

    appTest('Customers', (h) async {
      await big(h);
      expect(find.byType(LeadsScreen), findsOneWidget);
    }, location: '/leads');

    appTest('My employee', (h) async {
      await big(h);
      expect(find.byType(AgentScreen), findsOneWidget);
      await h.tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -2000),
      );
      await h.settle();
    }, location: '/agent');

    appTest(
      'first run',
      (h) async {
        await big(h);
        expect(find.byType(BusinessTypeScreen), findsOneWidget);
        await h.tapText('Clinic');
        expect(find.byType(NameVoiceScreen), findsOneWidget);
        await h.tapText('Continue');
        expect(find.byType(HearAiScreen), findsOneWidget);
      },
      location: '/onboarding',
      onboarded: false,
      overrides: () => [
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1, 8)),
      ],
    );
  });

  test('new-owner demo account is empty but named', () {
    final b = _newOwner();
    addTearDown(b.dispose);
    expect(b.leads, isEmpty);
    expect(b.calls, isEmpty);
    expect(b.leadSources, isEmpty);
    expect(b.business.name, isNotEmpty);
    expect(b.business.category, BusinessCategory.other);
  });
}

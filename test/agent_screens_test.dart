import 'package:callpilot/core/providers.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/features/agent/agent_screen.dart';
import 'package:callpilot/features/agent/edit_agent_screen.dart';
import 'package:callpilot/features/knowledge/teach_ai_screen.dart';
import 'package:callpilot/features/usage/usage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Scrolls the screen's main list until [finder] is built.
Future<void> _scrollTo(AppHarness h, Finder finder) async {
  await h.tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await h.tester.pump();
}

Future<void> _tapListItem(AppHarness h, Finder finder) async {
  await _scrollTo(h, finder);
  await h.tap(finder);
}

/// Identity text fields on the edit screen, in order: name, role, goal.
Finder _identityField(int i) => find.byType(TextField).at(i);

/// Whether the session provider reports a signed-in user.
bool? _signedIn(AppHarness h) => h.container.read(sessionProvider).value;

void main() {
  group('AgentScreen', () {
    appTest('shows the agent and links to its settings', (h) async {
      final a = h.backend.agent;
      expect(find.byType(AgentScreen), findsOneWidget);
      expect(find.text(a.name), findsWidgets);
      expect(find.text('Active'), findsOneWidget);

      await h.tapText('Edit AI Employee');
      expect(h.location, '/agent/edit');
      expect(find.byType(EditAgentScreen), findsOneWidget);
    }, location: '/agent');

    appTest('knowledge and usage cards open their screens', (h) async {
      await _tapListItem(h, find.text('Teach Your AI'));
      expect(h.location, '/agent/teach');
      expect(find.byType(TeachAiScreen), findsOneWidget);

      await h.go('/agent');
      await _tapListItem(h, find.textContaining('minutes left'));
      expect(h.location, '/usage');
      expect(find.byType(UsageScreen), findsOneWidget);
    }, location: '/agent');

    appTest('"More" links open callbacks and notifications', (h) async {
      await _tapListItem(h, find.text('Callbacks'));
      expect(h.location, '/callbacks');
      await h.go('/agent');
      await _tapListItem(h, find.text('Notifications'));
      expect(h.location, '/notifications');
    }, location: '/agent');

    appTest('sign out asks first, then ends the session', (h) async {
      await _tapListItem(h, find.text('Sign out'));
      expect(find.text('Sign out?'), findsOneWidget);
      await h.tapText('Cancel');
      expect(h.location, '/agent');
      expect(_signedIn(h), isTrue);

      final routerBefore = h.router;
      await _tapListItem(h, find.text('Sign out'));
      await h.tap(find.text('Sign out').last);
      expect(_signedIn(h), isFalse);
      // Signing out keeps the same router and lands on login, not on /splash.
      expect(identical(h.router, routerBefore), isTrue);
      expect(h.location, '/login');
      expect(find.byType(AgentScreen), findsNothing);
    }, location: '/agent');

    appTest('delete account asks first, then ends the session', (h) async {
      await _tapListItem(h, find.text('Delete account'));
      expect(find.text('Delete account?'), findsOneWidget);
      await h.tapText('Cancel');
      expect(h.location, '/agent');
      expect(_signedIn(h), isTrue);

      await _tapListItem(h, find.text('Delete account'));
      await h.tapText('Delete permanently');
      expect(_signedIn(h), isFalse);
      expect(h.location, '/login');
      expect(find.byType(AgentScreen), findsNothing);
    }, location: '/agent');
  });

  group('EditAgentScreen', () {
    appTest('saves edited identity fields to the backend', (h) async {
      // Pushed from the agent tab, as in the app, so saving pops back.
      await h.push('/agent/edit');
      final before = h.backend.agent;
      await h.tester.enterText(_identityField(0), 'Maya');
      await h.tester.enterText(_identityField(1), 'Sales Assistant');
      await h.tester.enterText(_identityField(2), 'Book more demos');
      await h.settle(2);
      await h.tapText('Save changes');

      final after = h.backend.agent;
      expect(after.name, 'Maya');
      expect(after.role, 'Sales Assistant');
      expect(after.goal, 'Book more demos');
      expect(after.id, before.id);
      expect(find.text('Maya updated ✓'), findsOneWidget);
      expect(h.location, '/agent');
    }, location: '/agent');

    appTest('rejects an invalid transfer number', (h) async {
      final transfer = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.phone,
      );
      await _scrollTo(h, transfer);
      await h.tester.enterText(transfer, '12');
      await h.tapText('Save changes');
      expect(find.text('Check the transfer number'), findsOneWidget);
      expect(h.location, '/agent/edit');
      expect(h.backend.agent.transferNumber, isNot('12'));
    }, location: '/agent/edit');

    appTest('an empty name is not saved', (h) async {
      final name = h.backend.agent.name;
      await h.tester.enterText(_identityField(0), '   ');
      await h.tapText('Save changes');
      expect(h.location, '/agent/edit');
      expect(h.backend.agent.name, name);
    }, location: '/agent/edit');

    appTest('languages, voice, personality, hours and status', (h) async {
      final before = h.backend.agent;

      // Toggle a language that is not selected yet.
      final lang = [
        'Tamil',
        'Telugu',
        'Marathi',
      ].firstWhere((l) => !before.languages.contains(l));
      await _tapListItem(h, find.text(lang));

      final voice = [
        'Warm · Female',
        'Calm · Female',
        'Friendly · Male',
        'Confident · Male',
      ].firstWhere((v) => v != before.voice);
      await _tapListItem(h, find.text(voice));

      final slider = find.byType(Slider);
      await _scrollTo(h, slider);
      await h.tester.tap(slider); // centre → formality 0.5
      await h.settle(2);

      final status = find.byType(SwitchListTile);
      await _tapListItem(h, status);
      expect(find.text('${before.name} is paused'), findsOneWidget);

      await h.tapText('Save changes');
      final after = h.backend.agent;
      expect(after.languages, contains(lang));
      expect(after.voice, voice);
      expect(after.formality, closeTo(0.5, 0.11));
      expect(after.status, AgentStatus.paused);
    }, location: '/agent/edit');

    appTest('teach card opens the knowledge screen', (h) async {
      await _tapListItem(h, find.text('Business Knowledge · Teach Your AI'));
      expect(h.location, '/agent/teach');
    }, location: '/agent/edit');
  });

  group('TeachAiScreen', () {
    Future<void> openSheet(AppHarness h, String option) async {
      await h.tapText('Add information');
      expect(find.text('Upload PDF'), findsOneWidget);
      await h.tapText(option);
    }

    appTest('lists existing knowledge sources', (h) async {
      for (final k in h.backend.knowledge.take(2)) {
        expect(find.text(k.title), findsOneWidget);
      }
      expect(find.text('Learned'), findsWidgets);
      expect(find.textContaining('Last updated'), findsOneWidget);
    }, location: '/agent/teach');

    appTest('pasted text is validated, learned and listed', (h) async {
      final count = h.backend.knowledge.length;
      await openSheet(h, 'Paste text');
      expect(find.text('Paste information'), findsOneWidget);

      // Too short → validation error, sheet stays open.
      final fields = find.byType(TextFormField);
      await h.tester.enterText(fields.last, 'short');
      await h.tapText('Add to your AI\'s knowledge');
      expect(find.text('Add a little more detail'), findsOneWidget);

      await h.tester.enterText(fields.first, 'Fees');
      await h.tester.enterText(
        fields.last,
        'NEET course fee is 52000 per year in three instalments.',
      );
      await h.tapText('Add to your AI\'s knowledge');
      // Processing (900 ms) then ready.
      await h.settle(10);

      expect(h.backend.knowledge, hasLength(count + 1));
      expect(h.backend.knowledge.first.title, 'Fees');
      expect(h.backend.knowledge.first.type, KnowledgeType.text);
      expect(find.textContaining('learned “Fees” ✓'), findsOneWidget);
    }, location: '/agent/teach');

    appTest('website input is normalised to https', (h) async {
      await openSheet(h, 'Add website');
      final field = find.byType(TextFormField);
      await h.tester.enterText(field, 'not a url');
      await h.tapText('Add to your AI\'s knowledge');
      expect(find.text('Enter a valid website'), findsOneWidget);

      await h.tester.enterText(field, 'abccoaching.in');
      await h.tapText('Add to your AI\'s knowledge');
      await h.settle(10);
      final added = h.backend.knowledge.first;
      expect(added.type, KnowledgeType.website);
      expect(added.detail, 'https://abccoaching.in');
    }, location: '/agent/teach');

    appTest('FAQ uses a default title when none is given', (h) async {
      await openSheet(h, 'Add FAQ');
      await h.tester.enterText(
        find.byType(TextFormField).last,
        'Q: Do you accept UPI?\nA: Yes, all UPI apps.',
      );
      await h.tapText('Add to your AI\'s knowledge');
      await h.settle(10);
      final added = h.backend.knowledge.first;
      expect(added.type, KnowledgeType.faq);
      expect(added.title, 'FAQ');
      expect(added.detail, '1 questions');
    }, location: '/agent/teach');

    appTest('a ready source can be removed', (h) async {
      final first = h.backend.knowledge.first;
      await h.tap(find.byTooltip('Remove').first);
      expect(h.backend.knowledge.any((k) => k.id == first.id), isFalse);
      expect(find.text('Removed “${first.title}”'), findsOneWidget);
    }, location: '/agent/teach');

    appTest(
      'empty state offers to add information',
      (h) async {
        expect(
          find.text('Your AI employee hasn\'t learned anything yet'),
          findsOneWidget,
        );
        await h.tapText('+ Add information');
        expect(find.text('Paste text'), findsOneWidget);
      },
      location: '/agent/teach',
      backend: () => MockBackend()..knowledge.clear(),
    );

    appTest(
      'polls processing sources until they are ready',
      (h) async {
        expect(find.text('Learning…'), findsOneWidget);
        // Still processing after one poll.
        await h.tester.pump(const Duration(seconds: 3));
        await h.settle(4);
        expect(find.text('Learning…'), findsOneWidget);

        // The backend finishes; the next poll picks it up.
        final i = h.backend.knowledge.indexWhere((k) => k.id == 'kn_proc');
        h.backend.knowledge[i] = h.backend.knowledge[i].copyWith(
          status: KnowledgeStatus.ready,
        );
        await h.tester.pump(const Duration(seconds: 3));
        await h.settle(6);
        expect(find.text('Learning…'), findsNothing);

        // Polling stops once nothing is processing.
        await h.tester.pump(const Duration(seconds: 7));
        await h.settle(2);
        expect(find.text('Learning…'), findsNothing);
      },
      location: '/agent/teach',
      backend: () => MockBackend()
        ..knowledge.insert(
          0,
          KnowledgeSource(
            id: 'kn_proc',
            type: KnowledgeType.text,
            title: 'Holiday hours',
            status: KnowledgeStatus.processing,
            updatedAt: DateTime(2026, 1, 1),
          ),
        ),
    );
  });
}

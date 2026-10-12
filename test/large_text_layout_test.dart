import 'package:callpilot/core/settings.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/shell/app_shell.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';
import 'helpers/real_fonts.dart';

/// Real-phone layout checks: a 412 dp wide screen (e.g. Samsung A34), the
/// real Geist / Mukta / Hind Siliguri fonts, and the owner's text size
/// turned all the way up. Any overflow fails the test on its own.
void main() {
  setUpAll(loadAppFonts);

  Future<void> phone(AppHarness h, {double scale = 2.0}) async {
    final t = h.tester;
    t.view.physicalSize = const Size(412, 2400);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await h.settle();
  }

  RenderParagraph paragraph(WidgetTester t, Finder f) =>
      t.renderObject<RenderParagraph>(
        find.descendant(of: f, matching: find.byType(RichText)).first,
      );

  for (final lang in AppLang.values) {
    appTest('${lang.code}: Home at 412 dp and text size 2.0 fits', (h) async {
      await h.container.read(languageProvider.notifier).set(lang);
      await phone(h);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('home-hero')), findsOneWidget);
      expect(h.tester.takeException(), isNull);

      // Tab bar: icons only (each screen has its name up top), but every
      // tab still has its name for screen readers and on long-press.
      final bar = find.byType(AppNavBar);
      final words = find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (w) => w is Text && !RegExp(r'^\d+\+?$').hasMatch(w.data ?? ''),
        ),
      );
      expect(words, findsNothing, reason: 'no tab captions');
      expect(
        find.descendant(of: bar, matching: find.byType(Tooltip)),
        findsNWidgets(5),
      );
      expect(h.tester.getSize(bar).height, greaterThanOrEqualTo(64));
    });
  }

  // Real names, including the one cut short on a Samsung A34 at Extra large
  // ("ABC Coaching…").
  for (final bizName in const [
    'Sharma Coaching Hub',
    'ABC Coaching Centre',
    'Bright Future Academy',
  ]) {
    appTest('Extra large: the business name "$bizName" is not cut short', (
      h,
    ) async {
      h.backend.business = h.backend.business.copyWith(name: bizName);
      h.backend.emitChanged('business');
      await h.container
          .read(textSizeProvider.notifier)
          .set(TextSize.extraLarge);
      await phone(h, scale: 1.15);
      expect(find.text(bizName), findsOneWidget);
      final p = paragraph(h.tester, find.byType(HomeScreen));
      expect(p.text.toPlainText(), contains('Good'));
      final name = h.tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text(bizName),
          matching: find.byType(RichText),
        ),
      );
      expect(name.didExceedMaxLines, isFalse);
      expect(h.tester.takeException(), isNull);
    });
  }

  appTest('Extra large: My employee rows show their values in full', (h) async {
    await h.container.read(textSizeProvider.notifier).set(TextSize.extraLarge);
    await phone(h, scale: 1.15);
    await h.go('/agent');
    final values = find.byKey(const Key('nav-row-value'));
    expect(values, findsWidgets);
    for (final e in values.evaluate()) {
      final p = h.tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byWidget(e.widget),
          matching: find.byType(RichText),
        ),
      );
      expect(p.didExceedMaxLines, isFalse);
    }
    expect(h.tester.takeException(), isNull);
  });

  appTest(
    'Onboarding: the language chip names the language',
    (h) async {
      await phone(h, scale: 1.6);
      expect(find.text('English'), findsOneWidget);
      final style = h.tester.widget<Text>(find.text('English')).style;
      expect(style?.color, isNotNull);
      expect(h.tester.takeException(), isNull);
    },
    location: '/onboarding',
    onboarded: false,
  );
}

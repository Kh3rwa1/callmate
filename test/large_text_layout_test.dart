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

      // Tab labels: one line each, never split inside a word, and never
      // wider than their tab.
      final tabWidth = 412 / 5;
      final bar = find.byType(AppNavBar);
      final labels = find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('nav-label-'),
        ),
      );
      expect(labels, findsNWidgets(5));
      for (final e in labels.evaluate()) {
        final text = e.widget as Text;
        expect(text.maxLines, 1);
        final box = h.tester.getRect(
          find.ancestor(
            of: find.byWidget(text),
            matching: find.byType(FittedBox),
          ),
        );
        expect(box.width, lessThanOrEqualTo(tabWidth), reason: text.data);
        final p = h.tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byWidget(text),
            matching: find.byType(RichText),
          ),
        );
        expect(p.didExceedMaxLines, isFalse, reason: text.data);
      }
      // Labels stay at least 12.5 at normal size.
      expect(AppNavBar.labelFontSize, greaterThanOrEqualTo(12.5));
    });
  }

  appTest('Extra large: the business name is not cut short', (h) async {
    h.backend.business = h.backend.business.copyWith(
      name: 'Sharma Coaching Hub',
    );
    h.backend.emitChanged('business');
    await h.container.read(textSizeProvider.notifier).set(TextSize.extraLarge);
    await phone(h, scale: 1.15);
    expect(find.text('Sharma Coaching Hub'), findsOneWidget);
    final p = paragraph(h.tester, find.byType(HomeScreen));
    expect(p.text.toPlainText(), contains('Good'));
    final name = h.tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Sharma Coaching Hub'),
        matching: find.byType(RichText),
      ),
    );
    expect(name.didExceedMaxLines, isFalse);
    expect(h.tester.takeException(), isNull);
  });

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

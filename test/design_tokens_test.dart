import 'package:callpilot/core/theme/app_colors.dart';
import 'package:callpilot/core/theme/app_theme.dart';
import 'package:callpilot/core/theme/contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contrast (WCAG AA)', () {
    test('ratio math matches known values', () {
      expect(Contrast.ratio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(Contrast.ratio(Colors.white, Colors.white), closeTo(1, 0.001));
    });

    for (final p in [AppPalette.light, AppPalette.dark]) {
      final mode = p.isDark ? 'dark' : 'light';

      test('$mode: text tokens on every page surface', () {
        final text = {
          'ink': p.ink,
          'inkSoft': p.inkSoft,
          'inkFaint': p.inkFaint,
          'brand': p.brand,
          'hot': p.hot,
          'warmInk': p.warmInk,
          'success': p.success,
          'accentInk': p.accentInk,
          'info': p.info,
          'whatsapp': p.whatsapp,
          'cold': p.cold,
        };
        final bgs = {
          'background': p.background,
          'surface': p.surface,
          'surfaceMuted': p.surfaceMuted,
        };
        for (final t in text.entries) {
          for (final b in bgs.entries) {
            expect(
              Contrast.ratio(t.value, b.value),
              greaterThanOrEqualTo(Contrast.aa),
              reason: '$mode ${t.key} on ${b.key}',
            );
          }
        }
      });

      test('$mode: tinted chips keep their text readable', () {
        final pairs = {
          'hot/hotSoft': (p.hot, p.hotSoft),
          'warmInk/warmSoft': (p.warmInk, p.warmSoft),
          'success/successSoft': (p.success, p.successSoft),
          'brand/brandSoft': (p.brand, p.brandSoft),
          'brandDeep/brandSoft': (p.brandDeep, p.brandSoft),
          'accentInk/accentSoft': (p.accentInk, p.accentSoft),
          'inkSoft/coldSoft': (p.inkSoft, p.coldSoft),
        };
        for (final e in pairs.entries) {
          expect(
            Contrast.ratio(e.value.$1, e.value.$2),
            greaterThanOrEqualTo(Contrast.aa),
            reason: '$mode ${e.key}',
          );
        }
      });

      test('$mode: filled buttons and hero surface', () {
        final pairs = {
          'onAccent/accent': (p.onAccent, p.accent),
          'onInverse/inverse': (p.onInverse, p.inverse),
          'white/strong': (Colors.white, p.strong),
          'onStrongSoft/strong': (p.onStrongSoft, p.strong),
          'accent/strong': (p.accent, p.strong),
          'white/hotFill': (Colors.white, p.hotFill),
          'white/whatsappFill': (Colors.white, p.whatsappFill),
          'white/brandFill': (Colors.white, p.brandFill),
        };
        for (final e in pairs.entries) {
          expect(
            Contrast.ratio(e.value.$1, e.value.$2),
            greaterThanOrEqualTo(Contrast.aa),
            reason: '$mode ${e.key}',
          );
        }
      });
    }
  });

  group('scales', () {
    test('spacing sits on the 4/8/12/16/24/32 scale', () {
      expect(
        [
          AppSpace.xs,
          AppSpace.sm,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.xxl,
        ],
        [4, 8, 12, 16, 24, 32],
      );
    });

    test('radii are 8/12/20', () {
      expect([AppRadius.sm, AppRadius.md, AppRadius.lg], [8, 12, 20]);
    });

    test('type scale: display is big, nothing under 13', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final theme = p.isDark ? AppTheme.dark() : AppTheme.light();
        final t = theme.textTheme;
        expect(t.displayLarge!.fontSize, inInclusiveRange(40, 48));
        final sizes = [
          t.displayLarge,
          t.displayMedium,
          t.displaySmall,
          t.headlineLarge,
          t.headlineMedium,
          t.headlineSmall,
          t.titleLarge,
          t.titleMedium,
          t.titleSmall,
          t.bodyLarge,
          t.bodyMedium,
          t.bodySmall,
          t.labelLarge,
          t.labelMedium,
          t.labelSmall,
        ].map((s) => s!.fontSize!);
        expect(sizes.every((s) => s >= 13), isTrue);
        expect(theme.textTheme.bodyLarge!.fontFamilyFallback, [
          'Mukta',
          'HindSiliguri',
        ]);
      }
    });
  });
}

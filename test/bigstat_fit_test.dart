import 'package:callpilot/core/theme/app_colors.dart';
import 'package:callpilot/core/theme/app_theme.dart';
import 'package:callpilot/core/widgets/world.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/real_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  for (final scale in [1.0, 1.15, 1.3, 1.5]) {
    testWidgets('two BigStats side by side never break a word at $scale', (
      t,
    ) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final (v, l) in [
                      (110, 'calls today'),
                      (79, 'talked today'),
                    ])
                      Expanded(
                        child: BigStat(
                          value: v,
                          label: l,
                          color: AppColors.ink,
                          size: 64,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final label in ['CALLS TODAY', 'TALKED TODAY']) {
        final p = t.renderObject<RenderParagraph>(find.text(label));
        expect(p.didExceedMaxLines, isFalse, reason: label);
      }
    });
  }
}

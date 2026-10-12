import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import 'app_colors.dart';

/// Corner radii: 8 (small tiles), 12 (inputs, rows), 20 (small cards),
/// 26 (cards, sheets, worlds). Buttons and chips are full pills.
class AppRadius {
  const AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const xl = 26.0;

  static const card = xl;
  static const cardSm = lg;
  static const button = 999.0;
  static const input = 16.0;
  static const chip = 999.0;
}

/// Spacing scale: 4 / 8 / 12 / 16 / 24 / 32. [page] is the screen gutter.
class AppSpace {
  const AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 20.0;
}

/// Elevation is mostly a 1 px border; shadows stay soft and short so cards
/// sit on the page instead of floating above it.
class AppShadows {
  const AppShadows._();

  /// Resting cards: printed on the paper, not floating above it.
  static List<BoxShadow> get card => const [];

  /// Raised state (hero, floating CTA, banners).
  static List<BoxShadow> get raised => AppColors.isDark
      ? const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1F1A1814),
            blurRadius: 28,
            spreadRadius: -6,
            offset: Offset(0, 14),
          ),
          BoxShadow(
            color: Color(0x0A1A1814),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ];

  static List<BoxShadow> glow(Color c) => [
    BoxShadow(
      color: c.withValues(alpha: AppColors.isDark ? 0.18 : 0.26),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Type scale (sizes in logical px). Display is for key numbers only and is
/// set in a condensed poster face ([AppTheme.displayFamily]); headlines are
/// an editorial serif ([AppTheme.serifFamily]); everything else is Geist.
class AppTypeScale {
  const AppTypeScale._();
  static const display = 72.0;
  static const displaySm = 40.0;
  static const headline = 30.0;
  static const title = 20.0;
  static const titleSm = 17.0;
  static const body = 16.0;
  static const bodySm = 15.0;
  static const caption = 13.0;
}

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Geist';

  /// Condensed poster face for big numbers ("110", "6.8 KM").
  static const displayFamily = 'Anton';

  /// Editorial serif for page and sheet titles.
  static const serifFamily = 'InstrumentSerif';

  /// A big number in [displayFamily]: tabular, tight, no faux bold.
  static TextStyle number(double size, {Color? color, double height = 0.95}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        fontWeight: FontWeight.w400,
        height: height,
        letterSpacing: 0,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// A serif title ("Customers", "Riya").
  static TextStyle serif(
    double size, {
    Color? color,
    bool italic = false,
    double height = 1.0,
  }) => TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: fontFallback,
    fontSize: size,
    fontWeight: FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    height: height,
    letterSpacing: -0.02 * size,
    color: color,
  );

  /// Small uppercase label ("01 · TODAY").
  static TextStyle eyebrow({Color? color, double size = 12.5}) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    height: 1.2,
    color: color,
  );

  /// Devanagari (Mukta) and Bengali (Hind Siliguri) glyphs: Geist covers
  /// Latin only. Both are humanist sans with a similar x-height and stroke
  /// contrast, so mixed-script lines look set in one family.
  static const fontFallback = ['Mukta', 'HindSiliguri'];

  static ThemeData light() => _build(AppPalette.light);
  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.light.brand,
      brightness: p.brightness,
      primary: p.isDark ? p.brand : p.brandFill,
      onPrimary: p.isDark ? p.onInverse : Colors.white,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkSoft,
      outline: p.border,
      outlineVariant: p.border,
      error: p.hot,
      inverseSurface: p.inverse,
      onInverseSurface: p.onInverse,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );

    TextStyle s(
      double size,
      FontWeight w, {
      Color? color,
      double? height,
      double letterSpacing = 0,
    }) => TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      fontSize: size,
      fontWeight: w,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

    final text = base.textTheme
        .apply(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          bodyColor: p.ink,
          displayColor: p.ink,
        )
        .copyWith(
          // Display: key numbers only (calls today, money). Semibold, tight
          // tracking, tabular figures. Titles step down clearly; body stays
          // regular weight for calm. Nothing goes below 13.
          // Display: key numbers only, in the condensed poster face.
          // Headlines: an editorial serif, regular weight, set big.
          displayLarge: number(AppTypeScale.display, color: p.ink),
          displayMedium: number(56, color: p.ink),
          displaySmall: number(AppTypeScale.displaySm, color: p.ink, height: 1),
          headlineLarge: serif(44, color: p.ink, height: 1.02),
          headlineMedium: serif(38, color: p.ink, height: 1.04),
          headlineSmall: serif(
            AppTypeScale.headline,
            color: p.ink,
            height: 1.1,
          ),
          titleLarge: s(
            AppTypeScale.title,
            FontWeight.w600,
            color: p.ink,
            height: 1.25,
            letterSpacing: -0.35,
          ),
          titleMedium: s(
            AppTypeScale.titleSm,
            FontWeight.w600,
            color: p.ink,
            height: 1.3,
            letterSpacing: -0.2,
          ),
          titleSmall: s(
            AppTypeScale.bodySm,
            FontWeight.w600,
            color: p.ink,
            letterSpacing: -0.1,
          ),
          bodyLarge: s(
            AppTypeScale.body,
            FontWeight.w400,
            color: p.ink,
            height: 1.5,
          ),
          bodyMedium: s(
            AppTypeScale.bodySm,
            FontWeight.w400,
            color: p.inkSoft,
            height: 1.5,
          ),
          bodySmall: s(
            AppTypeScale.caption,
            FontWeight.w400,
            color: p.inkFaint,
            height: 1.45,
          ),
          labelLarge: s(
            AppTypeScale.body,
            FontWeight.w600,
            letterSpacing: -0.1,
          ),
          labelMedium: s(
            AppTypeScale.caption,
            FontWeight.w500,
            color: p.inkSoft,
          ),
          labelSmall: s(
            AppTypeScale.caption,
            FontWeight.w600,
            color: p.inkFaint,
            letterSpacing: 0.3,
          ),
        );

    const buttonShape = StadiumBorder();
    final overlay = p.isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: p.surface,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: p.surface,
            systemNavigationBarIconBrightness: Brightness.dark,
          );

    return base.copyWith(
      textTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SoftPageTransitionsBuilder(),
          TargetPlatform.iOS: SoftPageTransitionsBuilder(),
          TargetPlatform.macOS: SoftPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: p.ink,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: overlay,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.inverse,
          foregroundColor: p.onInverse,
          disabledBackgroundColor: p.surfaceMuted,
          disabledForegroundColor: p.inkFaint,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: buttonShape,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: p.ink.withValues(alpha: 0.85), width: 1.4),
          shape: buttonShape,
          textStyle: text.labelLarge,
          backgroundColor: Colors.transparent,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.inverse,
        foregroundColor: p.onInverse,
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: p.inkFaint),
        labelStyle: text.bodyMedium,
        floatingLabelStyle: text.bodyMedium?.copyWith(color: p.ink),
        prefixIconColor: p.inkFaint,
        suffixIconColor: p.inkFaint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: p.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: p.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: p.ink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: p.hot, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: p.hot, width: 2),
        ),
        errorStyle: text.bodySmall?.copyWith(
          color: p.hot,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.inverse,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onInverse),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      // Selected segment is ink like a selected chip, never a lavender tint.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? p.ink : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? p.surface : p.ink,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: text.titleSmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.cardSm),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.light.ink,
        actionTextColor: p.accent,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkSoft,
        textColor: p.ink,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.success : p.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.success : p.surface,
        ),
        checkColor: WidgetStateProperty.all(
          p.isDark ? p.onInverse : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: p.border, width: 1.5),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.ink,
        inactiveTrackColor: p.surfaceMuted,
        thumbColor: p.ink,
        overlayColor: p.ink.withValues(alpha: 0.10),
        valueIndicatorColor: AppPalette.light.ink,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(
          color: Colors.white,
        ),
        trackHeight: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.ink,
        linearTrackColor: p.surfaceMuted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppPalette.light.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.hotFill,
        textColor: Colors.white,
      ),
    );
  }
}

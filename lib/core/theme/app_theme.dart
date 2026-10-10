import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import 'app_colors.dart';

/// Corner radii: 8 (chips, small tiles), 12 (buttons, inputs, rows),
/// 20 (cards and sheets). Pills use [chip].
class AppRadius {
  const AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;

  static const card = lg;
  static const cardSm = md;
  static const button = md;
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

  /// Resting cards: a whisper of shadow under the 1 px border.
  static List<BoxShadow> get card => AppColors.isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0A15163A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x0515163A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ];

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
            color: Color(0x1A15163A),
            blurRadius: 24,
            spreadRadius: -4,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x0A000000),
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

/// Type scale (sizes in logical px). Display is for key numbers only.
class AppTypeScale {
  const AppTypeScale._();
  static const display = 44.0;
  static const displaySm = 34.0;
  static const headline = 26.0;
  static const title = 20.0;
  static const titleSm = 17.0;
  static const body = 16.0;
  static const bodySm = 15.0;
  static const caption = 13.0;
}

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Geist';

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
          displayLarge: s(
            AppTypeScale.display,
            FontWeight.w600,
            color: p.ink,
            height: 1.02,
            letterSpacing: -1.6,
          ),
          displayMedium: s(
            40,
            FontWeight.w600,
            color: p.ink,
            height: 1.04,
            letterSpacing: -1.4,
          ),
          displaySmall: s(
            AppTypeScale.displaySm,
            FontWeight.w600,
            color: p.ink,
            height: 1.08,
            letterSpacing: -1.1,
          ),
          headlineLarge: s(
            30,
            FontWeight.w600,
            color: p.ink,
            height: 1.1,
            letterSpacing: -0.9,
          ),
          headlineMedium: s(
            28,
            FontWeight.w600,
            color: p.ink,
            height: 1.12,
            letterSpacing: -0.8,
          ),
          headlineSmall: s(
            AppTypeScale.headline - 3,
            FontWeight.w600,
            color: p.ink,
            height: 1.18,
            letterSpacing: -0.5,
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

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
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
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: p.border, width: 1.2),
          shape: buttonShape,
          textStyle: text.labelLarge,
          backgroundColor: p.surface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
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
        floatingLabelStyle: text.bodyMedium?.copyWith(color: p.brand),
        prefixIconColor: p.inkFaint,
        suffixIconColor: p.inkFaint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: p.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: p.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: p.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: p.hot, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
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
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
        backgroundColor: p.strong,
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
        activeTrackColor: p.brand,
        inactiveTrackColor: p.brandSoft,
        thumbColor: p.brand,
        overlayColor: p.brand.withValues(alpha: 0.12),
        valueIndicatorColor: p.strong,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(
          color: Colors.white,
        ),
        trackHeight: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.brand,
        linearTrackColor: p.surfaceMuted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.strong,
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

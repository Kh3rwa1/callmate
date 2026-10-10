import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import 'app_colors.dart';

class AppRadius {
  static const card = 20.0;
  static const cardSm = 16.0;
  static const button = 14.0;
  static const chip = 999.0;
}

class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const page = 22.0;
}

/// Shadows follow the active palette: soft and wide on paper, deeper but
/// quieter in the dark (where elevation mostly comes from surface colour).
class AppShadows {
  const AppShadows._();

  /// Lifts cards without a visible "slab".
  static List<BoxShadow> get card => AppColors.isDark
      ? const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0A14121F),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ];

  /// Raised state (pressed / floating CTA / banners).
  static List<BoxShadow> get raised => AppColors.isDark
      ? const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1A1B1530),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ];

  static List<BoxShadow> glow(Color c) => [
    BoxShadow(
      color: c.withValues(alpha: AppColors.isDark ? 0.22 : 0.32),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'PlusJakartaSans';

  /// Devanagari and Bengali glyphs: Plus Jakarta Sans covers Latin only.
  static const fontFallback = ['Hind', 'HindSiliguri'];

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
          displayMedium: s(
            44,
            FontWeight.w800,
            color: p.ink,
            height: 1.05,
            letterSpacing: -1.6,
          ),
          displaySmall: s(
            36,
            FontWeight.w800,
            color: p.ink,
            height: 1.08,
            letterSpacing: -1.2,
          ),
          headlineMedium: s(
            30,
            FontWeight.w800,
            color: p.ink,
            height: 1.1,
            letterSpacing: -1.0,
          ),
          headlineSmall: s(
            24,
            FontWeight.w800,
            color: p.ink,
            height: 1.15,
            letterSpacing: -0.6,
          ),
          titleLarge: s(20, FontWeight.w800, color: p.ink, letterSpacing: -0.4),
          titleMedium: s(
            17,
            FontWeight.w700,
            color: p.ink,
            letterSpacing: -0.2,
          ),
          titleSmall: s(15, FontWeight.w700, color: p.ink),
          bodyLarge: s(16, FontWeight.w500, color: p.ink, height: 1.5),
          bodyMedium: s(15, FontWeight.w500, color: p.inkSoft, height: 1.45),
          bodySmall: s(13, FontWeight.w500, color: p.inkFaint, height: 1.4),
          labelLarge: s(16, FontWeight.w700),
          labelMedium: s(13, FontWeight.w700, color: p.inkSoft),
          labelSmall: s(
            12,
            FontWeight.w800,
            color: p.inkFaint,
            letterSpacing: 1.1,
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
        backgroundColor: p.inverse,
        actionTextColor: p.isDark ? p.brandFill : const Color(0xFF7FB4FF),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: p.onInverse,
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
        valueIndicatorColor: p.inverse,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(color: p.onInverse),
        trackHeight: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.brand,
        linearTrackColor: p.surfaceMuted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverse,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: text.bodySmall?.copyWith(color: p.onInverse),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.hotFill,
        textColor: Colors.white,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens, mirroring the Callmate web app's palette and scale so the two
/// clients look like the same product.
class AppColors {
  const AppColors._();

  static const Color canvas = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF172033);
  static const Color inkSoft = Color(0xFF6B7280);

  static const Color brand = Color(0xFF18C97A);
  static const Color brandSoft = Color(0xFFE6F9F0);

  static const Color blue = Color(0xFF4C7DFF);
  static const Color blueSoft = Color(0xFFEAEFFF);

  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleSoft = Color(0xFFF2ECFF);

  static const Color amber = Color(0xFFFFC857);
  static const Color amberInk = Color(0xFF7A4D00);
  static const Color amberSoft = Color(0xFFFFF6E3);

  static const Color coral = Color(0xFFFF6B6B);
  static const Color coralSoft = Color(0xFFFFECEC);

  static const Color border = Color(0xFFE8EDF3);
  static const Color secondary = Color(0xFFF1F5F9);
}

/// Corner radii, matching the web app's `--radius` scale.
class AppRadius {
  const AppRadius._();

  static const double sm = 10;
  static const double md = 13;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 26;
  static const double xxxl = 34;
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Soft elevation used by cards, matching the web app's `--shadow-card`.
const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x0A172033), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x08172033), blurRadius: 2, offset: Offset(0, 1)),
];

const List<BoxShadow> kBrandShadow = [
  BoxShadow(color: Color(0x4718C97A), blurRadius: 24, offset: Offset(0, 10)),
];

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        primary: AppColors.brand,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
    );

    final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: text.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.ink),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      dividerColor: AppColors.border,
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// Text styles used across the app, matching the web app's `.text-*` utilities.
class AppText {
  const AppText._();

  static TextStyle display = GoogleFonts.plusJakartaSans(
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w800,
  );

  static TextStyle hero = GoogleFonts.plusJakartaSans(
    fontSize: 27,
    height: 1.2,
    fontWeight: FontWeight.w800,
  );

  static TextStyle title = GoogleFonts.plusJakartaSans(
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  static TextStyle body = GoogleFonts.plusJakartaSans(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w500,
  );

  static TextStyle caption = GoogleFonts.plusJakartaSans(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static TextStyle label = GoogleFonts.plusJakartaSans(
    fontSize: 11,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w700,
  );
}

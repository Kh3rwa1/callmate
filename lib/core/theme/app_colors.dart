import 'package:flutter/material.dart';

/// Every colour the app uses, for one brightness.
///
/// Text tokens are checked for WCAG AA (4.5:1) against `background`,
/// `surface`, `surfaceMuted` and their own `*Soft` tint in both palettes.
/// `*Fill` tokens are backgrounds that carry white text.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.hairline,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.brand,
    required this.brandSoft,
    required this.brandDeep,
    required this.brandFill,
    required this.success,
    required this.successSoft,
    required this.warm,
    required this.warmSoft,
    required this.warmInk,
    required this.hot,
    required this.hotSoft,
    required this.hotFill,
    required this.cold,
    required this.coldSoft,
    required this.info,
    required this.infoSoft,
    required this.whatsapp,
    required this.whatsappSoft,
    required this.whatsappFill,
    required this.mascotHalo,
    required this.inverse,
    required this.onInverse,
    required this.strong,
    required this.bubble,
    required this.bubbleBorder,
    required this.shadow,
    required this.skeletonHighlight,
  });

  final Brightness brightness;

  // Surfaces
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color hairline;

  // Text
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;

  // Brand
  final Color brand;
  final Color brandSoft;
  final Color brandDeep;
  final Color brandFill;

  // Semantic
  final Color success;
  final Color successSoft;
  final Color warm;
  final Color warmSoft;
  final Color warmInk;
  final Color hot;
  final Color hotSoft;
  final Color hotFill;
  final Color cold;
  final Color coldSoft;
  final Color info;
  final Color infoSoft;

  // WhatsApp handoff
  final Color whatsapp;
  final Color whatsappSoft;
  final Color whatsappFill;

  final Color mascotHalo;

  /// Primary buttons, selected chips, snackbars: ink in light, paper in dark.
  final Color inverse;
  final Color onInverse;

  /// Dark "hero" cards (plan, live campaign, banners) in both modes; always
  /// carries white text.
  final Color strong;

  /// WhatsApp draft bubble.
  final Color bubble;
  final Color bubbleBorder;

  /// Base colour of card shadows.
  final Color shadow;
  final Color skeletonHighlight;

  bool get isDark => brightness == Brightness.dark;

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F7FC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDF2FA),
    border: Color(0xFFDFE6F2),
    hairline: Color(0x0F000000),
    ink: Color(0xFF0E173A),
    inkSoft: Color(0xFF4A5470),
    inkFaint: Color(0xFF5F6880),
    brand: Color(0xFF0058E6),
    brandSoft: Color(0xFFE5EFFF),
    brandDeep: Color(0xFF003FB8),
    brandFill: Color(0xFF0562FD),
    success: Color(0xFF137336),
    successSoft: Color(0xFFE6F6EC),
    warm: Color(0xFFF59E0B),
    warmSoft: Color(0xFFFEF3DC),
    warmInk: Color(0xFFA64B07),
    hot: Color(0xFFC8222B),
    hotSoft: Color(0xFFFDEBEC),
    hotFill: Color(0xFFC8222B),
    cold: Color(0xFF5F6880),
    coldSoft: Color(0xFFEDF0F6),
    info: Color(0xFF0369A1),
    infoSoft: Color(0xFFE3F4FC),
    whatsapp: Color(0xFF0F7A3F),
    whatsappSoft: Color(0xFFE3F6EA),
    whatsappFill: Color(0xFF0F7A3F),
    mascotHalo: Color(0xFFE0F0FA),
    inverse: Color(0xFF0E173A),
    onInverse: Color(0xFFFFFFFF),
    strong: Color(0xFF0B1430),
    bubble: Color(0xFFE7F8DD),
    bubbleBorder: Color(0xFFCDEBC0),
    shadow: Color(0xFF0E173A),
    skeletonHighlight: Color(0xFFF8FAFE),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0A0F1C),
    surface: Color(0xFF121A2B),
    surfaceMuted: Color(0xFF1A2438),
    border: Color(0xFF26324A),
    hairline: Color(0x14FFFFFF),
    ink: Color(0xFFEEF2FA),
    inkSoft: Color(0xFFB4BDD0),
    inkFaint: Color(0xFF8F99AF),
    brand: Color(0xFF7FB4FF),
    brandSoft: Color(0xFF14254A),
    brandDeep: Color(0xFFB5D3FF),
    brandFill: Color(0xFF1F5EF5),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF12301F),
    warm: Color(0xFFFBBF24),
    warmSoft: Color(0xFF3A2C0C),
    warmInk: Color(0xFFFBBF24),
    hot: Color(0xFFFF7A7F),
    hotSoft: Color(0xFF3B1619),
    hotFill: Color(0xFFD92D35),
    cold: Color(0xFFA3ABBE),
    coldSoft: Color(0xFF1E2738),
    info: Color(0xFF5CC8FF),
    infoSoft: Color(0xFF0D2B3B),
    whatsapp: Color(0xFF4BD48A),
    whatsappSoft: Color(0xFF123222),
    whatsappFill: Color(0xFF117A40),
    mascotHalo: Color(0xFF16244A),
    inverse: Color(0xFFEEF2FA),
    onInverse: Color(0xFF0E173A),
    strong: Color(0xFF16213A),
    bubble: Color(0xFF173323),
    bubbleBorder: Color(0xFF24503A),
    shadow: Color(0xFF000000),
    skeletonHighlight: Color(0xFF222D44),
  );

  static AppPalette of(Brightness b) => b == Brightness.dark ? dark : light;
}

/// The active palette as static getters, so call sites read
/// `AppColors.ink` in either brightness.
///
/// The app sets [palette] from the resolved theme (see `PaletteScope`) and
/// rebuilds the tree when it changes, so widgets never keep stale colours.
/// Because these are getters, they can't be used in `const` expressions.
class AppColors {
  const AppColors._();

  /// The active palette. Set by `PaletteScope`; read through the getters.
  static AppPalette palette = AppPalette.light;

  static bool get isDark => palette.isDark;

  // Surfaces
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceMuted => palette.surfaceMuted;
  static Color get border => palette.border;
  static Color get hairline => palette.hairline;

  // Text
  static Color get ink => palette.ink;
  static Color get inkSoft => palette.inkSoft;
  static Color get inkFaint => palette.inkFaint;

  // Brand
  static Color get brand => palette.brand;
  static Color get brandSoft => palette.brandSoft;
  static Color get brandDeep => palette.brandDeep;
  static Color get brandFill => palette.brandFill;

  // Semantic
  static Color get success => palette.success;
  static Color get successSoft => palette.successSoft;
  static Color get warm => palette.warm;
  static Color get warmSoft => palette.warmSoft;
  static Color get warmInk => palette.warmInk;
  static Color get hot => palette.hot;
  static Color get hotSoft => palette.hotSoft;
  static Color get hotFill => palette.hotFill;
  static Color get cold => palette.cold;
  static Color get coldSoft => palette.coldSoft;
  static Color get info => palette.info;
  static Color get infoSoft => palette.infoSoft;

  // WhatsApp handoff
  static Color get whatsapp => palette.whatsapp;
  static Color get whatsappSoft => palette.whatsappSoft;
  static Color get whatsappFill => palette.whatsappFill;

  static Color get mascotHalo => palette.mascotHalo;
  static Color get inverse => palette.inverse;
  static Color get onInverse => palette.onInverse;
  static Color get strong => palette.strong;
  static Color get bubble => palette.bubble;
  static Color get bubbleBorder => palette.bubbleBorder;
  static Color get skeletonHighlight => palette.skeletonHighlight;

  /// Fixed brand gradient of the hero card (identical in both modes).
  static const heroGradient = [
    Color(0xFF2E7DFF),
    Color(0xFF0562FD),
    Color(0xFF0038C8),
  ];

  /// Status dot on dark/brand surfaces.
  static const liveDot = Color(0xFF86EFAC);
}

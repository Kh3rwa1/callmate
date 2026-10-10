import 'package:flutter/material.dart';

/// Every colour the app uses, for one brightness.
///
/// The system has three layers:
/// * **Neutrals** – cool paper/ink with a hint of indigo, so the app reads
///   calm and expensive instead of "default blue".
/// * **Brand** – one deep indigo for structure: links, selected tabs and
///   chips, the hero surface.
/// * **Signature** – one warm marigold ([accent]) reserved for wins and the
///   single primary action on a screen. It always carries dark text
///   ([onAccent]); white on marigold fails contrast.
///
/// Semantic colours are fixed in meaning everywhere: [hot] = ready to buy,
/// [warm] = interested, [success] = done/checked, [cold] = neutral. Change
/// indicators ("vs last week") never use red/green – they are neutral chips
/// with ▲/▼ so they don't fight the hot numbers next to them.
///
/// Text tokens meet WCAG AA (4.5:1) on `background`, `surface` and
/// `surfaceMuted` in both palettes – enforced by `test/design_tokens_test.dart`.
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
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentInk,
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
    required this.onStrongSoft,
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

  // Brand (deep indigo)
  final Color brand;
  final Color brandSoft;
  final Color brandDeep;
  final Color brandFill;

  // Signature accent (marigold): wins + the one primary action.
  final Color accent;
  final Color onAccent;
  final Color accentSoft;

  /// Accent used as text/icon on light surfaces (darker for contrast).
  final Color accentInk;

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

  /// Selected chips and filled buttons: the brand indigo, white on top.
  final Color inverse;
  final Color onInverse;

  /// Deep indigo "hero" surface (Home hero, plan, live campaign); always
  /// carries white text.
  final Color strong;

  /// Secondary text on [strong].
  final Color onStrongSoft;

  /// WhatsApp draft bubble.
  final Color bubble;
  final Color bubbleBorder;

  /// Base colour of card shadows.
  final Color shadow;
  final Color skeletonHighlight;

  bool get isDark => brightness == Brightness.dark;

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEFF6),
    border: Color(0xFFE3E3EE),
    hairline: Color(0x14161640),
    ink: Color(0xFF15163A),
    inkSoft: Color(0xFF46476A),
    inkFaint: Color(0xFF5B5C7C),
    brand: Color(0xFF3D35C8),
    brandSoft: Color(0xFFECEBFD),
    brandDeep: Color(0xFF2B249A),
    brandFill: Color(0xFF3D35C8),
    accent: Color(0xFFF5A524),
    onAccent: Color(0xFF1C1405),
    accentSoft: Color(0xFFFFF3DC),
    accentInk: Color(0xFF8A5200),
    success: Color(0xFF137336),
    successSoft: Color(0xFFE6F4EA),
    warm: Color(0xFFEA580C),
    warmSoft: Color(0xFFFFEDE0),
    warmInk: Color(0xFFAD3E06),
    hot: Color(0xFFC8222B),
    hotSoft: Color(0xFFFDECEC),
    hotFill: Color(0xFFC8222B),
    cold: Color(0xFF5E5F7E),
    coldSoft: Color(0xFFEFEFF6),
    info: Color(0xFF0369A1),
    infoSoft: Color(0xFFE3F4FC),
    whatsapp: Color(0xFF0F7A3F),
    whatsappSoft: Color(0xFFE3F6EA),
    whatsappFill: Color(0xFF0F7A3F),
    mascotHalo: Color(0xFFE6ECFF),
    inverse: Color(0xFF3D35C8),
    onInverse: Color(0xFFFFFFFF),
    strong: Color(0xFF1E1B5C),
    onStrongSoft: Color(0xFFC9C7EE),
    bubble: Color(0xFFE7F8DD),
    bubbleBorder: Color(0xFFCDEBC0),
    shadow: Color(0xFF15163A),
    skeletonHighlight: Color(0xFFF8F8FC),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0B17),
    surface: Color(0xFF14142A),
    surfaceMuted: Color(0xFF1C1C38),
    border: Color(0xFF2A2A4A),
    hairline: Color(0x14FFFFFF),
    ink: Color(0xFFEEEEF9),
    inkSoft: Color(0xFFB9B9D3),
    inkFaint: Color(0xFF9A9AB9),
    brand: Color(0xFFABA6FF),
    brandSoft: Color(0xFF221F55),
    brandDeep: Color(0xFFD0CDFF),
    brandFill: Color(0xFF4B44DB),
    accent: Color(0xFFF5A524),
    onAccent: Color(0xFF1C1405),
    accentSoft: Color(0xFF3A2A0A),
    accentInk: Color(0xFFFFC15C),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF12301F),
    warm: Color(0xFFFB923C),
    warmSoft: Color(0xFF3A220F),
    warmInk: Color(0xFFFDA769),
    hot: Color(0xFFFF7A7F),
    hotSoft: Color(0xFF3B1619),
    hotFill: Color(0xFFD92D35),
    cold: Color(0xFFA6A7BF),
    coldSoft: Color(0xFF1E1E36),
    info: Color(0xFF5CC8FF),
    infoSoft: Color(0xFF0D2B3B),
    whatsapp: Color(0xFF4BD48A),
    whatsappSoft: Color(0xFF123222),
    whatsappFill: Color(0xFF117A40),
    mascotHalo: Color(0xFF1E1D4A),
    inverse: Color(0xFF5A53E6),
    onInverse: Color(0xFFFFFFFF),
    strong: Color(0xFF1C1A48),
    onStrongSoft: Color(0xFFC9C7EE),
    bubble: Color(0xFF173323),
    bubbleBorder: Color(0xFF24503A),
    shadow: Color(0xFF000000),
    skeletonHighlight: Color(0xFF24244A),
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

  // Signature accent
  static Color get accent => palette.accent;
  static Color get onAccent => palette.onAccent;
  static Color get accentSoft => palette.accentSoft;
  static Color get accentInk => palette.accentInk;

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
  static Color get onStrongSoft => palette.onStrongSoft;
  static Color get bubble => palette.bubble;
  static Color get bubbleBorder => palette.bubbleBorder;
  static Color get skeletonHighlight => palette.skeletonHighlight;

  /// Status dot on dark/brand surfaces.
  static const liveDot = Color(0xFF86EFAC);
}

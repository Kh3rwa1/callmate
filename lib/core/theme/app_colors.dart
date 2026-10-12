import 'package:flutter/material.dart';

/// Every colour the app uses, for one brightness.
///
/// The system has three layers:
/// * **Neutrals** – warm paper and ink, like a printed page, so the colour
///   in the app comes from the product, not the chrome.
/// * **Brand** – one cobalt (the mascot's blue) for links and the Home
///   world. Selected chips and filled buttons are plain ink.
/// * **Signature** – one acid lime ([accent]) for the single loudest action
///   on a coloured world and for wins. It always carries ink text
///   ([onAccent]).
///
/// Each tab also lives in its own colour world – see [AppWorld].
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
    background: Color(0xFFF3EEE4),
    surface: Color(0xFFFFFCF6),
    surfaceMuted: Color(0xFFEAE3D5),
    border: Color(0xFFDDD4C3),
    hairline: Color(0x1A2A2010),
    ink: Color(0xFF1A1814),
    inkSoft: Color(0xFF48423A),
    inkFaint: Color(0xFF5E574B),
    brand: Color(0xFF2440D8),
    brandSoft: Color(0xFFE4E8F7),
    brandDeep: Color(0xFF1A2C9E),
    brandFill: Color(0xFF2440D8),
    accent: Color(0xFFCDEB3F),
    onAccent: Color(0xFF1A1814),
    accentSoft: Color(0xFFEEF6C6),
    accentInk: Color(0xFF475400),
    success: Color(0xFF1B7136),
    successSoft: Color(0xFFE0EFDC),
    warm: Color(0xFFE2560E),
    warmSoft: Color(0xFFFCE6D4),
    warmInk: Color(0xFFA3400A),
    hot: Color(0xFFBC2519),
    hotSoft: Color(0xFFFBE3DC),
    hotFill: Color(0xFFCF3523),
    cold: Color(0xFF5B5549),
    coldSoft: Color(0xFFEAE3D5),
    info: Color(0xFF0A5F95),
    infoSoft: Color(0xFFDDECF5),
    whatsapp: Color(0xFF0E7038),
    whatsappSoft: Color(0xFFDDF1E2),
    whatsappFill: Color(0xFF0F7A3F),
    mascotHalo: Color(0xFFE3E7FF),
    inverse: Color(0xFF1A1814),
    onInverse: Color(0xFFFFFCF6),
    strong: Color(0xFF2440D8),
    onStrongSoft: Color(0xFFDCE1FF),
    bubble: Color(0xFFE4F5D6),
    bubbleBorder: Color(0xFFC9E6B5),
    shadow: Color(0xFF1A1814),
    skeletonHighlight: Color(0xFFF8F4EC),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF121110),
    surface: Color(0xFF1C1A17),
    surfaceMuted: Color(0xFF26231F),
    border: Color(0xFF35312B),
    hairline: Color(0x14FFFFFF),
    ink: Color(0xFFF3EEE4),
    inkSoft: Color(0xFFCBC3B4),
    inkFaint: Color(0xFFA59D8E),
    brand: Color(0xFF9DABFF),
    brandSoft: Color(0xFF23273A),
    brandDeep: Color(0xFFCBD2FF),
    brandFill: Color(0xFF3350E6),
    accent: Color(0xFFCDEB3F),
    onAccent: Color(0xFF1A1814),
    accentSoft: Color(0xFF2B3109),
    accentInk: Color(0xFFD7F05C),
    success: Color(0xFF63D383),
    successSoft: Color(0xFF14301D),
    warm: Color(0xFFFB923C),
    warmSoft: Color(0xFF3A230F),
    warmInk: Color(0xFFFDA769),
    hot: Color(0xFFFF8A78),
    hotSoft: Color(0xFF3B1813),
    hotFill: Color(0xFFD23A26),
    cold: Color(0xFFADA595),
    coldSoft: Color(0xFF26231F),
    info: Color(0xFF6CC6F5),
    infoSoft: Color(0xFF0F2A38),
    whatsapp: Color(0xFF55D48E),
    whatsappSoft: Color(0xFF133222),
    whatsappFill: Color(0xFF117A40),
    mascotHalo: Color(0xFF1D2350),
    inverse: Color(0xFFF3EEE4),
    onInverse: Color(0xFF1A1814),
    strong: Color(0xFF2440D8),
    onStrongSoft: Color(0xFFDCE1FF),
    bubble: Color(0xFF173323),
    bubbleBorder: Color(0xFF24503A),
    shadow: Color(0xFF000000),
    skeletonHighlight: Color(0xFF2E2B26),
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

/// Each tab owns one loud colour, like a magazine section: the top of the
/// tab is painted in it and the tab bar pill takes it when selected. The
/// rest of the page stays on calm paper so lists remain easy to read.
enum AppWorld {
  /// Home – cobalt, the mascot's blue.
  home(
    bg: Color(0xFF2440D8),
    fg: Color(0xFFFFFFFF),
    soft: Color(0xFFDCE1FF),
    cta: Color(0xFFCDEB3F),
    onCta: Color(0xFF1A1814),
  ),

  /// Customers – ink black with lime, like a ledger.
  leads(
    bg: Color(0xFF1A1814),
    fg: Color(0xFFFFFCF6),
    soft: Color(0xFFC4BCAD),
    cta: Color(0xFFCDEB3F),
    onCta: Color(0xFF1A1814),
  ),

  /// Calls – tomato red, the colour of a phone ringing.
  calls(
    bg: Color(0xFFC0341F),
    fg: Color(0xFFFFFFFF),
    soft: Color(0xFFFFE3DC),
    cta: Color(0xFFFFFCF6),
    onCta: Color(0xFF1A1814),
  ),

  /// Messages – chartreuse, close to a chat bubble without copying one.
  messages(
    bg: Color(0xFFD5EE5A),
    fg: Color(0xFF1A1814),
    soft: Color(0xFF3B4410),
    cta: Color(0xFF1A1814),
    onCta: Color(0xFFFFFCF6),
  ),

  /// My employee – marigold, warm like a name badge.
  agent(
    bg: Color(0xFFF3B530),
    fg: Color(0xFF1A1814),
    soft: Color(0xFF4F3A07),
    cta: Color(0xFF1A1814),
    onCta: Color(0xFFFFFCF6),
  );

  const AppWorld({
    required this.bg,
    required this.fg,
    required this.soft,
    required this.cta,
    required this.onCta,
  });

  /// The world's paint.
  final Color bg;

  /// Main text and icons on [bg].
  final Color fg;

  /// Secondary text on [bg].
  final Color soft;

  /// The one button on [bg], with [onCta] text.
  final Color cta;
  final Color onCta;

  /// The paint to use right now: the ink world lifts a step in dark mode
  /// so it still reads as a block on the near-black page.
  Color get paint =>
      this == AppWorld.leads && AppColors.isDark ? const Color(0xFF2A2621) : bg;

  /// Light status-bar icons on dark worlds, dark ones on bright worlds.
  bool get isDarkBg => bg.computeLuminance() < 0.3;

  /// Per tab index (Home · Customers · Calls · Messages · My employee).
  static AppWorld ofTab(int i) => values[i.clamp(0, values.length - 1)];
}

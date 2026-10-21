import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// System bar style for edge-to-edge (MainActivity calls enableEdgeToEdge):
/// both bars are transparent over the app, with icons that suit what is
/// behind them. Android 15+ ignores bar colours; before that a bar with a
/// colour (Flutter's SystemUiOverlayStyle.light/dark use black) is painted
/// over the content drawn behind it, so the colours must be transparent.
SystemUiOverlayStyle systemBarsStyle({
  required bool darkBehindStatusBar,
  required bool darkBehindNavBar,
}) => SystemUiOverlayStyle(
  statusBarColor: const Color(0x00000000),
  systemNavigationBarColor: const Color(0x00000000),
  systemNavigationBarDividerColor: const Color(0x00000000),
  statusBarIconBrightness: darkBehindStatusBar
      ? Brightness.light
      : Brightness.dark,
  // iOS reads the background brightness instead of the icon colour.
  statusBarBrightness: darkBehindStatusBar ? Brightness.dark : Brightness.light,
  systemNavigationBarIconBrightness: darkBehindNavBar
      ? Brightness.light
      : Brightness.dark,
);

extension NavBarPadding on EdgeInsets {
  /// This padding plus the navigation bar's height, for a screen's main
  /// scrolling list: edge-to-edge draws the bar over the app, and a list with
  /// its own padding doesn't add the bar's height by itself. Adds nothing
  /// where the bar is already accounted for (SafeArea, a bottom app bar).
  EdgeInsets withNavBar(BuildContext context) =>
      copyWith(bottom: bottom + MediaQuery.paddingOf(context).bottom);
}

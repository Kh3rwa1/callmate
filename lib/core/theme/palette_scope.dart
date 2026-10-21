import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'system_bars.dart';

/// Points [AppColors] at the palette of the resolved theme.
///
/// [AppColors] getters are static, so widgets don't depend on anything that
/// would rebuild them when the phone switches between light and dark. When
/// the brightness changes this marks the whole subtree for rebuild once
/// (keeping all state, like a hot reload), so no widget keeps stale colours.
class PaletteScope extends StatefulWidget {
  const PaletteScope({super.key, required this.child});
  final Widget child;

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  @override
  Widget build(BuildContext context) {
    final next = AppPalette.of(Theme.of(context).brightness);
    if (!identical(AppColors.palette, next)) {
      AppColors.palette = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildSubtree();
      });
    }
    // System bars for the whole app, re-applied after every frame. MaterialApp
    // sets SystemUiOverlayStyle.light/dark (black navigation bar) on each
    // build; a one-off SystemChrome call would lose to it. Headers with their
    // own region (AppBar, World) still decide the status bar icons.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayFor(next),
      child: widget.child,
    );
  }

  void _rebuildSubtree() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  static SystemUiOverlayStyle _overlayFor(AppPalette p) => systemBarsStyle(
    darkBehindStatusBar: p.isDark,
    darkBehindNavBar: p.isDark,
  );
}

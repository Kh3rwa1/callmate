import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

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
      SystemChrome.setSystemUIOverlayStyle(_overlayFor(next));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildSubtree();
      });
    }
    return widget.child;
  }

  void _rebuildSubtree() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  static SystemUiOverlayStyle _overlayFor(AppPalette p) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: p.surface,
    systemNavigationBarIconBrightness: p.isDark
        ? Brightness.light
        : Brightness.dark,
  );
}

import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's bundled fonts (Geist + the Devanagari/Bengali fallbacks)
/// into the test engine, so layout uses real glyph widths instead of the
/// test font's wide squares. Overflow checks are only meaningful with this.
Future<void> loadAppFonts() async {
  if (_loaded) return;
  _loaded = true;
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await family('Geist', [for (final w in weights) 'Geist-$w.ttf']);
  await family('Mukta', [for (final w in weights) 'Mukta-$w.ttf']);
  await family('HindSiliguri', [
    for (final w in weights) 'HindSiliguri-$w.ttf',
  ]);
}

bool _loaded = false;

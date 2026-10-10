import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import 'providers.dart';
import 'storage/local_prefs.dart';

/// Appearance and language choices. Both default to following the phone and
/// survive sign-out (they belong to the device, not the account).

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => switch (_prefs(ref)?.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs(
      ref,
    )?.setThemeMode(mode == ThemeMode.system ? null : mode.name);
  }
}

/// The owner's chosen language, or null to follow the phone.
final languageProvider = NotifierProvider<LanguageController, AppLang?>(
  LanguageController.new,
);

class LanguageController extends Notifier<AppLang?> {
  @override
  AppLang? build() {
    final code = _prefs(ref)?.language;
    return code == null ? null : AppLang.fromCode(code);
  }

  Future<void> set(AppLang? lang) async {
    state = lang;
    await _prefs(ref)?.setLanguage(lang?.code);
  }
}

/// In-app text size, applied on top of the phone's own font size.
enum TextSize {
  normal(1.0),
  large(1.2),
  extraLarge(1.4);

  const TextSize(this.factor);

  /// Multiplier on top of the system text scale.
  final double factor;

  String? get wire => switch (this) {
    TextSize.normal => null,
    TextSize.large => 'large',
    TextSize.extraLarge => 'xlarge',
  };

  static TextSize parse(String? v) => switch (v) {
    'large' => TextSize.large,
    'xlarge' => TextSize.extraLarge,
    _ => TextSize.normal,
  };
}

final textSizeProvider = NotifierProvider<TextSizeController, TextSize>(
  TextSizeController.new,
);

class TextSizeController extends Notifier<TextSize> {
  @override
  TextSize build() => TextSize.parse(_prefs(ref)?.textSize);

  Future<void> set(TextSize size) async {
    state = size;
    await _prefs(ref)?.setTextSize(size.wire);
  }
}

/// Smallest and largest overall text scale (phone setting × in-app size).
const kMinTextScale = 0.85;
const kMaxTextScale = 2.0;

/// The text scaler the app runs with: the phone's scale times the in-app
/// [TextSize], kept between [kMinTextScale] and [kMaxTextScale].
TextScaler appTextScaler(TextScaler system, TextSize size) {
  final base = system.scale(100) / 100;
  final f = (base * size.factor).clamp(kMinTextScale, kMaxTextScale);
  return TextScaler.linear(f);
}

LocalPrefs? _prefs(Ref ref) {
  try {
    return ref.read(localPrefsProvider);
  } catch (_) {
    return null;
  }
}

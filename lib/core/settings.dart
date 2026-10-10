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

LocalPrefs? _prefs(Ref ref) {
  try {
    return ref.read(localPrefsProvider);
  } catch (_) {
    return null;
  }
}

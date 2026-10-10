import 'package:flutter/widgets.dart';

/// Languages the app speaks. Business owners pick theirs on the sign-in
/// screen or in Settings; otherwise the phone's language decides.
enum AppLang {
  en('en', 'English'),
  hi('hi', 'हिन्दी'),
  bn('bn', 'বাংলা');

  const AppLang(this.code, this.nativeName);
  final String code;

  /// The language's name in itself (shown in the language picker).
  final String nativeName;

  Locale get locale => Locale(code, 'IN');

  static AppLang fromCode(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => AppLang.en);

  static const locales = [
    Locale('en', 'IN'),
    Locale('hi', 'IN'),
    Locale('bn', 'IN'),
  ];
}

/// UI strings for one language.
///
/// Strings live next to each other in all three languages, grouped by
/// feature in `s_<feature>.dart` extensions, so a reviewer proofreads a
/// screen's Hindi and Bengali side by side with the English:
///
/// ```dart
/// String get leadsTitle => pick('Customers', 'ग्राहक', 'গ্রাহক');
/// ```
@immutable
class S {
  const S(this.lang);
  final AppLang lang;

  static const en = S(AppLang.en);

  static S of(BuildContext context) =>
      S(AppLang.fromCode(Localizations.maybeLocaleOf(context)?.languageCode));

  bool get isEn => lang == AppLang.en;

  /// The string for the active language.
  String pick(String en, String hi, String bn) => switch (lang) {
    AppLang.en => en,
    AppLang.hi => hi,
    AppLang.bn => bn,
  };

  /// English needs singular/plural; Hindi and Bengali use one form here.
  String plural(int n, String one, String many, String hi, String bn) =>
      pick(n == 1 ? one : many, hi, bn);

  @override
  bool operator ==(Object other) => other is S && other.lang == lang;

  @override
  int get hashCode => lang.hashCode;
}

extension SContext on BuildContext {
  /// Strings in the active language: `context.s.leadsTitle`.
  S get s => S.of(this);
}

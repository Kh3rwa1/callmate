import 'package:intl/intl.dart';

import '../../l10n/s.dart';

/// Dates, times and numbers in the UI's language.
///
/// Digits stay Latin in every language (as in the phone numbers and prices
/// the owner already reads); month and weekday names are translated.
class Fmt {
  const Fmt._();

  static const _monthsHi = [
    'जन',
    'फ़र',
    'मार्च',
    'अप्रैल',
    'मई',
    'जून',
    'जुलाई',
    'अग',
    'सित',
    'अक्टू',
    'नव',
    'दिस',
  ];
  static const _monthsBn = [
    'জানু',
    'ফেব',
    'মার্চ',
    'এপ্রি',
    'মে',
    'জুন',
    'জুলাই',
    'আগ',
    'সেপ্ট',
    'অক্টো',
    'নভে',
    'ডিসে',
  ];
  static const _daysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
  static const _daysBn = [
    'সোম',
    'মঙ্গল',
    'বুধ',
    'বৃহস্পতি',
    'শুক্র',
    'শনি',
    'রবি',
  ];

  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  static String duration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  /// "12 Oct" / "12 अक्टू" / "12 অক্টো".
  static String dayMonth(DateTime d, {AppLang lang = AppLang.en}) =>
      switch (lang) {
        AppLang.en => DateFormat('d MMM').format(d),
        AppLang.hi => '${d.day} ${_monthsHi[d.month - 1]}',
        AppLang.bn => '${d.day} ${_monthsBn[d.month - 1]}',
      };

  /// "Sat, 12 Oct".
  static String weekdayDayMonth(DateTime d, {AppLang lang = AppLang.en}) =>
      switch (lang) {
        AppLang.en => DateFormat('EEE, d MMM').format(d),
        AppLang.hi => '${_daysHi[d.weekday - 1]}, ${dayMonth(d, lang: lang)}',
        AppLang.bn => '${_daysBn[d.weekday - 1]}, ${dayMonth(d, lang: lang)}',
      };

  /// "12 Oct 2026".
  static String date(DateTime d, {AppLang lang = AppLang.en}) =>
      lang == AppLang.en
      ? DateFormat('d MMM yyyy').format(d)
      : '${dayMonth(d, lang: lang)} ${d.year}';

  static String relative(
    DateTime d, {
    DateTime? now,
    AppLang lang = AppLang.en,
  }) {
    final s = S(lang);
    final n = now ?? DateTime.now();
    final diff = n.difference(d);
    if (diff.isNegative) return friendlyFuture(d, now: n, lang: lang);
    if (diff.inSeconds < 60) return s.pick('just now', 'अभी', 'এইমাত্র');
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return s.pick('$m min ago', '$m मिनट पहले', '$m মিনিট আগে');
    }
    if (diff.inHours < 24 && n.day == d.day) {
      final h = diff.inHours;
      return s.pick('${h}h ago', '$h घंटे पहले', '$h ঘণ্টা আগে');
    }
    if (diff.inDays < 2 && n.day != d.day) {
      return s.pick('Yesterday', 'बीते कल', 'গতকাল');
    }
    return dayMonth(d, lang: lang);
  }

  /// "Today", "Tomorrow", "Yesterday" or "Sat, 12 Oct".
  static String dayLabel(
    DateTime d, {
    DateTime? now,
    AppLang lang = AppLang.en,
  }) {
    final s = S(lang);
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    return switch (day.difference(today).inDays) {
      0 => s.pick('Today', 'आज', 'আজ'),
      1 => s.pick('Tomorrow', 'कल', 'আগামীকাল'),
      -1 => s.pick('Yesterday', 'बीते कल', 'গতকাল'),
      _ => weekdayDayMonth(d, lang: lang),
    };
  }

  /// "Today, 6:00 PM" / "Tomorrow, 6:00 PM" / "Sat, 12 Oct · 6:00 PM"
  static String friendlyFuture(
    DateTime d, {
    DateTime? now,
    AppLang lang = AppLang.en,
  }) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    final delta = day.difference(today).inDays;
    final t = time(d);
    if (delta >= -1 && delta <= 1) {
      return '${dayLabel(d, now: n, lang: lang)}, $t';
    }
    return '${weekdayDayMonth(d, lang: lang)} · $t';
  }

  /// "tomorrow at 6:00 PM" / "today at 6:00 PM" / "on Sat, 12 Oct at 6:00 PM"
  static String callbackPhrase(
    DateTime d, {
    DateTime? now,
    AppLang lang = AppLang.en,
  }) {
    final s = S(lang);
    final n = now ?? DateTime.now();
    final delta = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(n.year, n.month, n.day)).inDays;
    final t = time(d);
    if (delta == 0) return s.pick('today at $t', 'आज $t पर', 'আজ $t-এ');
    if (delta == 1) {
      return s.pick('tomorrow at $t', 'कल $t पर', 'আগামীকাল $t-এ');
    }
    final day = weekdayDayMonth(d, lang: lang);
    return s.pick('on $day at $t', '$day, $t पर', '$day, $t-এ');
  }

  static String inr(num v) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(v);

  static String number(num v) => NumberFormat.decimalPattern('en_IN').format(v);

  static String greeting([DateTime? now, AppLang lang = AppLang.en]) {
    final s = S(lang);
    final h = (now ?? DateTime.now()).hour;
    if (h < 12) return s.pick('Good morning', 'सुप्रभात', 'সুপ্রভাত');
    if (h < 17) return s.pick('Good afternoon', 'नमस्ते', 'শুভ দুপুর');
    return s.pick('Good evening', 'शुभ संध्या', 'শুভ সন্ধ্যা');
  }

  static String hour(int h) {
    final dt = DateTime(2024, 1, 1, h);
    return DateFormat('h a').format(dt);
  }
}

/// Glues digit groups ("64,358") with a word joiner so a line never breaks
/// inside a number ("64," / "358").
String keepNumbersTogether(String text) =>
    text.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]},\u2060${m[2]}');

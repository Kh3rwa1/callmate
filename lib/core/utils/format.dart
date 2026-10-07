import 'package:intl/intl.dart';

class Fmt {
  const Fmt._();

  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  static String duration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  static String relative(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(d);
    if (diff.isNegative) return friendlyFuture(d, now: n);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && n.day == d.day) return '${diff.inHours}h ago';
    if (diff.inDays < 2 && n.day != d.day) return 'Yesterday';
    return DateFormat('d MMM').format(d);
  }

  /// "Today, 6:00 PM" / "Tomorrow, 6:00 PM" / "Sat, 12 Oct · 6:00 PM"
  static String friendlyFuture(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    final delta = day.difference(today).inDays;
    final t = time(d);
    if (delta == 0) return 'Today, $t';
    if (delta == 1) return 'Tomorrow, $t';
    if (delta == -1) return 'Yesterday, $t';
    return '${DateFormat('EEE, d MMM').format(d)} · $t';
  }

  /// "tomorrow at 6:00 PM" / "today at 6:00 PM" / "on Sat, 12 Oct at 6:00 PM"
  static String callbackPhrase(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final delta = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(n.year, n.month, n.day)).inDays;
    final t = time(d);
    if (delta == 0) return 'today at $t';
    if (delta == 1) return 'tomorrow at $t';
    return 'on ${DateFormat('EEE, d MMM').format(d)} at $t';
  }

  static String inr(num v) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(v);

  static String number(num v) => NumberFormat.decimalPattern('en_IN').format(v);

  static String greeting([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String hour(int h) {
    final dt = DateTime(2024, 1, 1, h);
    return DateFormat('h a').format(dt);
  }
}

/// Phone number normalisation with sane Indian defaults.
///
/// Accepts things like "98765 43210", "+91-98765-43210", "09876543210",
/// "919876543210", "0091 98765 43210" and returns E.164 digits without '+',
/// e.g. "919876543210" — exactly what wa.me expects.
class PhoneUtils {
  const PhoneUtils._();

  static const defaultCountryCode = '91';

  /// Returns digits-only international number, or null if invalid.
  static String? normalize(
    String? input, {
    String countryCode = defaultCountryCode,
  }) {
    if (input == null) return null;
    var raw = input.trim();
    if (raw.isEmpty) return null;

    final hasPlus = raw.startsWith('+');
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    if (!hasPlus && digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (!hasPlus) {
      // Domestic trunk prefix "0" (e.g. 09876543210)
      if (digits.length == 11 && digits.startsWith('0')) {
        digits = digits.substring(1);
      }
      if (digits.length == 10) digits = '$countryCode$digits';
    }

    // Indian numbers: 91 + 10 digit mobile starting 6-9.
    if (digits.startsWith('91') && digits.length == 12) {
      final national = digits.substring(2);
      return RegExp(r'^[6-9]\d{9}$').hasMatch(national) ? digits : null;
    }

    // Other countries: E.164 allows 8..15 digits total.
    if (digits.length >= 8 && digits.length <= 15 && !digits.startsWith('0')) {
      // A bare 10-digit-with-91 mistake like "91" + 9 digits is invalid.
      if (digits.startsWith('91')) return null;
      return digits;
    }
    return null;
  }

  static bool isValid(String? input) => normalize(input) != null;

  /// Pretty display: +91 98765 43210
  static String display(String? input) {
    final n = normalize(input);
    if (n == null) return input ?? '';
    if (n.startsWith('91') && n.length == 12) {
      return '+91 ${n.substring(2, 7)} ${n.substring(7)}';
    }
    return '+$n';
  }

  /// Masked for logs/analytics: +91 98•••••210
  static String masked(String? input) {
    final n = normalize(input);
    if (n == null || n.length < 6) return '•••';
    return '+${n.substring(0, 4)}•••••${n.substring(n.length - 3)}';
  }
}

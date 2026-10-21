import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../data/models/models.dart';

/// Opens a URL in an external app (the browser / UPI app for payment pages).
/// Overridden in tests.
final externalUrlLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum CheckoutOutcome {
  /// Payment page opened outside the app; refresh when the user returns.
  opened,

  /// Paid without leaving the app (mock backend).
  paid,

  /// Pay by UPI to the business's UPI ID, then report the UTR.
  upi,

  /// The UTR of a UPI payment was sent; support confirms it.
  upiSubmitted,

  /// Online payments are not set up; show the "we'll contact you" message.
  notConfigured,

  /// A top-up needs an active plan (`plan_not_active`).
  notActive,
  failed,
}

/// Starts checkout for [planId] and opens the payment page.
/// Returns the outcome, for [CheckoutOutcome.failed] a message if known, and
/// for [CheckoutOutcome.upi] the payment to make.
Future<(CheckoutOutcome, String?, UpiCheckout?)> startCheckout(
  WidgetRef ref, {
  String planId = 'starter',
}) async {
  try {
    final start = await ref.read(usageRepoProvider).checkout(planId: planId);
    final upi = start.upi;
    if (upi != null) return (CheckoutOutcome.upi, null, upi);
    final url = start.url;
    if (url == null) {
      ref.read(dataVersionProvider.notifier).bump();
      return (CheckoutOutcome.paid, null, null);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return (CheckoutOutcome.failed, null, null);
    }
    final ok = await ref.read(externalUrlLauncherProvider)(uri);
    return ok
        ? (CheckoutOutcome.opened, null, null)
        : (CheckoutOutcome.failed, null, null);
  } on ApiException catch (e) {
    if (e.code == 'billing_not_configured') {
      return (CheckoutOutcome.notConfigured, null, null);
    }
    if (e.code == 'plan_not_active') {
      return (CheckoutOutcome.notActive, null, null);
    }
    return (CheckoutOutcome.failed, e.message, null);
  } catch (_) {
    return (CheckoutOutcome.failed, null, null);
  }
}

/// [raw] with spaces and dashes removed when that leaves exactly 12 digits
/// (a UPI transaction's UTR), else null.
String? normalizeUtr(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{12}$').hasMatch(digits) ? digits : null;
}

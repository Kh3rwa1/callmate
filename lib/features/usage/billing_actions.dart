import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

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

  /// Online payments are not set up; show the "we'll contact you" message.
  notConfigured,
  failed,
}

/// Starts checkout for [planId] and opens the payment page.
/// Returns the outcome and, for [CheckoutOutcome.failed], a message if known.
Future<(CheckoutOutcome, String?)> startCheckout(
  WidgetRef ref, {
  String planId = 'starter',
}) async {
  try {
    final url = await ref.read(usageRepoProvider).checkout(planId: planId);
    if (url == null) {
      ref.read(dataVersionProvider.notifier).bump();
      return (CheckoutOutcome.paid, null);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return (CheckoutOutcome.failed, null);
    final ok = await ref.read(externalUrlLauncherProvider)(uri);
    return ok ? (CheckoutOutcome.opened, null) : (CheckoutOutcome.failed, null);
  } on ApiException catch (e) {
    if (e.code == 'billing_not_configured') {
      return (CheckoutOutcome.notConfigured, null);
    }
    return (CheckoutOutcome.failed, e.message);
  } catch (_) {
    return (CheckoutOutcome.failed, null);
  }
}

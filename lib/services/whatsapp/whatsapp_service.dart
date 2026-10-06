import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/phone.dart';

/// Result of a WhatsApp handoff. We can only ever know that WhatsApp was
/// OPENED – never that the message was sent. UI copy must respect that.
enum WhatsAppOpenResult { opened, invalidPhone, emptyMessage, notInstalled }

abstract class WhatsAppService {
  Future<WhatsAppOpenResult> openChat({required String phone, required String message});
  Future<void> copyMessage(String message);
  Future<void> shareMessage(String message);
}

/// Click-to-chat implementation. No WhatsApp Business API, no auto-send.
class WhatsAppDeepLinkService implements WhatsAppService {
  const WhatsAppDeepLinkService();

  /// Builds `https://wa.me/<digits>?text=<encoded>` (public for tests).
  static Uri? buildUri({required String phone, required String message}) {
    final digits = PhoneUtils.normalize(phone);
    if (digits == null) return null;
    final text = message.trim();
    return Uri.parse('https://wa.me/$digits${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
  }

  /// Native scheme – opens the app directly when installed.
  static Uri? buildNativeUri({required String phone, required String message}) {
    final digits = PhoneUtils.normalize(phone);
    if (digits == null) return null;
    return Uri.parse('whatsapp://send?phone=$digits&text=${Uri.encodeComponent(message.trim())}');
  }

  @override
  Future<WhatsAppOpenResult> openChat({required String phone, required String message}) async {
    if (message.trim().isEmpty) return WhatsAppOpenResult.emptyMessage;
    final web = buildUri(phone: phone, message: message);
    final native = buildNativeUri(phone: phone, message: message);
    if (web == null || native == null) return WhatsAppOpenResult.invalidPhone;

    try {
      // Prefer the installed app (requires LSApplicationQueriesSchemes /
      // <queries> entries – see Info.plist and AndroidManifest.xml).
      if (await canLaunchUrl(native)) {
        if (await launchUrl(native, mode: LaunchMode.externalApplication)) return WhatsAppOpenResult.opened;
      }
    } catch (_) {}

    try {
      // Universal link: opens WhatsApp if present, otherwise WhatsApp Web.
      if (await launchUrl(web, mode: LaunchMode.externalNonBrowserApplication)) return WhatsAppOpenResult.opened;
    } catch (_) {}

    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) return WhatsAppOpenResult.opened;
    } catch (_) {}

    return WhatsAppOpenResult.notInstalled;
  }

  @override
  Future<void> copyMessage(String message) => Clipboard.setData(ClipboardData(text: message));

  @override
  Future<void> shareMessage(String message) => SharePlus.instance.share(ShareParams(text: message));
}

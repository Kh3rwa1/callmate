import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import '../../core/storage/local_prefs.dart';

/// Referral codes use these characters only (no 0/O, 1/I/L), 6 long.
/// Must match `REFERRAL_ALPHABET` in backend/src/services/referrals.ts.
final _codeRe = RegExp(r'^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$');

/// Upper-cases and strips spaces/dashes; null unless it is a valid code.
String? normalizeReferralCode(String? raw) {
  if (raw == null) return null;
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return _codeRe.hasMatch(code) ? code : null;
}

/// The referral code in a Play install referrer string, e.g.
/// `utm_source=landing&utm_campaign=ABC234` (set by the /get landing page).
/// Also accepts `ref=ABC234`. Returns null for organic installs.
String? refCodeFromInstallReferrer(String? referrer) {
  if (referrer == null || referrer.trim().isEmpty) return null;
  Map<String, String> params;
  try {
    params = Uri.splitQueryString(referrer.trim());
  } catch (_) {
    return null;
  }
  return normalizeReferralCode(params['ref']) ??
      normalizeReferralCode(params['utm_campaign']);
}

/// Reads the Google Play install referrer once (first launch), extracts the
/// referral code and remembers it so signup can send it.
class InstallReferrerService {
  InstallReferrerService(this._prefs, {Future<String?> Function()? read})
    : _read = read ?? _readFromPlay;

  final LocalPrefs? _prefs;
  final Future<String?> Function() _read;

  static Future<String?> _readFromPlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final details = await PlayInstallReferrer.installReferrer;
    return details.installReferrer;
  }

  /// The stored code, or (first time only) the code from the Play referrer.
  Future<String?> referralCode() async {
    final prefs = _prefs;
    if (prefs != null && prefs.installReferrerChecked) {
      return prefs.installReferralCode;
    }
    String? code;
    try {
      code = refCodeFromInstallReferrer(await _read());
    } catch (_) {
      // Play services missing or the referrer service is unavailable:
      // try again next launch.
      return null;
    }
    await prefs?.setInstallReferral(code);
    return code;
  }
}

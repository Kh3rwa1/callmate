import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive local flags (onboarding state etc.).
class LocalPrefs {
  LocalPrefs(this._p);
  final SharedPreferences _p;

  static Future<LocalPrefs> create() async {
    final prefs = LocalPrefs(await SharedPreferences.getInstance());
    await prefs.purgeLegacySecrets();
    return prefs;
  }

  static const _onboarded = 'onboarding.completed';
  static const _agentTested = 'onboarding.agent_tested';
  static const _serverUrl = 'config.server_url';

  /// Older builds could store a Sarvam API key here in plain text. The app
  /// now only talks to Sarvam through the backend proxy, so it is purged.
  static const _legacySarvamKey = 'config.sarvam_key';

  bool get onboarded => _p.getBool(_onboarded) ?? false;
  Future<void> setOnboarded(bool v) => _p.setBool(_onboarded, v);

  bool get agentTested => _p.getBool(_agentTested) ?? false;
  Future<void> setAgentTested(bool v) => _p.setBool(_agentTested, v);

  String? get serverUrl => _p.getString(_serverUrl);
  Future<void> setServerUrl(String? v) =>
      v == null ? _p.remove(_serverUrl) : _p.setString(_serverUrl, v);

  /// Removes any secrets persisted by older app versions.
  Future<void> purgeLegacySecrets() async {
    if (_p.containsKey(_legacySarvamKey)) await _p.remove(_legacySarvamKey);
  }

  Future<void> reset() async {
    await _p.remove(_onboarded);
    await _p.remove(_agentTested);
  }
}

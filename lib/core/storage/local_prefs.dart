import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive local flags (onboarding state etc.).
class LocalPrefs {
  LocalPrefs(this._p);
  final SharedPreferences _p;

  static Future<LocalPrefs> create() async => LocalPrefs(await SharedPreferences.getInstance());

  static const _onboarded = 'onboarding.completed';
  static const _agentTested = 'onboarding.agent_tested';

  bool get onboarded => _p.getBool(_onboarded) ?? false;
  Future<void> setOnboarded(bool v) => _p.setBool(_onboarded, v);

  bool get agentTested => _p.getBool(_agentTested) ?? false;
  Future<void> setAgentTested(bool v) => _p.setBool(_agentTested, v);

  Future<void> reset() async {
    await _p.remove(_onboarded);
    await _p.remove(_agentTested);
  }
}

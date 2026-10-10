import '../../l10n/s.dart';

/// The two voices an owner chooses between. Stored on the agent as the
/// existing labels, so the edit screen's four options keep working.
const femaleVoice = 'Warm · Female';
const maleVoice = 'Friendly · Male';

/// True for a man's voice. Checks "female" first because it contains "male".
bool isMaleVoice(String? voice) {
  final v = (voice ?? '').toLowerCase();
  if (v.contains('female') || v.contains('woman')) return false;
  return v.contains('male') || v.contains('man');
}

/// Sarvam Bulbul v4 Flash persona for this gender and app language.
/// IDs from docs.sarvam.ai (Voices → Bulbul v4 Flash); "meera" is a v1 name
/// and is not in the v4 catalog.
String sarvamSpeaker({required bool male, required AppLang lang}) =>
    switch (lang) {
      AppLang.hi => male ? 'shubh_hi_customer' : 'ritu_hi_customer',
      AppLang.bn => male ? 'bappa_bn_conversation' : 'roopa_bn_conversational',
      // English for Indian callers: the English–Hindi code-mixed personas.
      AppLang.en => male ? 'sunny_enhi_customer' : 'ishita_enhi_customer',
    };

/// BCP-47 code Sarvam expects for [lang].
String sarvamLanguageCode(AppLang lang) => switch (lang) {
  AppLang.hi => 'hi-IN',
  AppLang.bn => 'bn-IN',
  AppLang.en => 'en-IN',
};

/// Agent variables that make the test call sound like the employee the
/// owner set up: right gender, right language.
Map<String, String> voiceVariables({
  required String? voice,
  required AppLang lang,
}) {
  final male = isMaleVoice(voice);
  return {
    'gender': male ? 'male' : 'female',
    'voice': male ? 'male' : 'female',
    'speaker': sarvamSpeaker(male: male, lang: lang),
    'language_code': sarvamLanguageCode(lang),
    'tts_model': 'bulbul:v4-flash',
  };
}

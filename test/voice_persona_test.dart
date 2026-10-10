import 'package:callpilot/l10n/s.dart';
import 'package:callpilot/services/voice/voice_persona.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the gender from every voice label we have stored', () {
    expect(isMaleVoice('Warm · Female'), isFalse);
    expect(isMaleVoice('Calm · Female'), isFalse);
    expect(isMaleVoice('Friendly Female (Hindi/English)'), isFalse);
    expect(isMaleVoice('Friendly · Male'), isTrue);
    expect(isMaleVoice('Confident · Male'), isTrue);
    expect(isMaleVoice(null), isFalse);
    expect(isMaleVoice(''), isFalse);
  });

  test('picks a Bulbul v4 voice per gender and language', () {
    for (final lang in AppLang.values) {
      final f = sarvamSpeaker(male: false, lang: lang);
      final m = sarvamSpeaker(male: true, lang: lang);
      expect(f, isNot(m));
      expect(f, isNot('meera'));
      expect(f, matches(RegExp(r'^[a-z]+_(hi|bn|en|enhi)_[a-z]+$')));
      expect(m, matches(RegExp(r'^[a-z]+_(hi|bn|en|enhi)_[a-z]+$')));
    }
    expect(
      sarvamSpeaker(male: true, lang: AppLang.bn),
      'bappa_bn_conversation',
    );
  });

  test('voiceVariables carries gender, speaker and language', () {
    final v = voiceVariables(voice: 'Friendly · Male', lang: AppLang.bn);
    expect(v['gender'], 'male');
    expect(v['speaker'], 'bappa_bn_conversation');
    expect(v['language_code'], 'bn-IN');
    expect(v['tts_model'], 'bulbul:v4-flash');
  });
}

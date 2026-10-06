import 'dart:js_interop';

@JS('speakAgentText')
external void _speakAgentText(JSString text);

@JS('stopAgentSpeech')
external void _stopAgentSpeech();

@JS('playBase64Audio')
external void _playBase64Audio(JSString base64);

void speakAgentText(String text) {
  try {
    _speakAgentText(text.toJS);
  } catch (_) {}
}

void stopAgentSpeech() {
  try {
    _stopAgentSpeech();
  } catch (_) {}
}

void playBase64Audio(String base64) {
  try {
    _playBase64Audio(base64.toJS);
  } catch (_) {}
}

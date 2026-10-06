import 'dart:js_interop';

@JS('speakAgentText')
external void _speakAgentText(JSString text);

@JS('stopAgentSpeech')
external void _stopAgentSpeech();

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

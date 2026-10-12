import 'package:flutter_test/flutter_test.dart';
import 'package:sarvamconv_ai_sdk/sarvamconv_ai_sdk.dart';

void main() {
  test('transcription events reach the app instead of being dropped', () {
    final msg = parseServerMessage({
      'timestamp': 1.0,
      'origin': 'server',
      'type': 'server.event.transcription',
      'role': 'bot',
      'content': 'We offer NEET and JEE batches.',
    });
    expect(msg, isA<ServerRawEvent>());
    final e = msg as ServerRawEvent;
    expect(e.rawType, 'server.event.transcription');
    expect(e.data['content'], 'We offer NEET and JEE batches.');
  });

  test('types the SDK has never heard of come through too', () {
    final msg = parseServerMessage({'type': 'server.event.something_new'});
    expect(msg, isA<ServerRawEvent>());
    expect((msg as ServerRawEvent).type, ServerMsgType.unknown);
  });
}

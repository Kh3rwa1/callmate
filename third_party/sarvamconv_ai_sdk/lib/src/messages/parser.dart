// Message parsing utilities.

import 'audio.dart';
import 'base.dart';
import 'events.dart';
import 'system.dart';
import 'text.dart';
import 'types.dart';

/// Parse a server message from a raw JSON-like map.
///
/// Returns the appropriate typed message instance.
/// Throws [ArgumentError] if message type is unknown or parsing fails.
ServerMsgBase parseServerMessage(Map<String, dynamic> data) {
  final typeStr = data['type'] as String?;
  if (typeStr == null) {
    throw ArgumentError('Missing "type" field in server message');
  }

  final type = ServerMsgType.fromString(typeStr);
  // CallPilot patch: hand unknown types to the app instead of throwing.
  if (type == null) return ServerRawEvent.fromJson(data);

  switch (type) {
    case ServerMsgType.textChunk:
      return ServerTextChunkMsg.fromJson(data);
    case ServerMsgType.text:
      return ServerTextMsg.fromJson(data);
    case ServerMsgType.audioChunk:
      return ServerAudioChunkMsg.fromJson(data);
    case ServerMsgType.ping:
      return ServerPingMsg.fromJson(data);
    case ServerMsgType.interactionEnd:
      return ServerInteractionEndEvent.fromJson(data);
    case ServerMsgType.interactionConnected:
      return ServerInteractionConnectedEvent.fromJson(data);
    case ServerMsgType.userInterrupt:
      return ServerUserInterruptEvent.fromJson(data);
    default:
      // CallPilot patch: known but unparsed types (speech start/end,
      // transcription, …) reach the app as raw events.
      return ServerRawEvent.fromJson(data);
  }
}

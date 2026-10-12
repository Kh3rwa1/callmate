// Text message types for sending and receiving text.

import 'base.dart';
import 'types.dart';

/// Server text message - complete text from the server.
class ServerTextMsg extends ServerMsgBase {
  final String text;

  ServerTextMsg({
    required this.text,
    required super.timestamp,
  }) : super(type: ServerMsgType.text);

  factory ServerTextMsg.fromJson(Map<String, dynamic> json) {
    return ServerTextMsg(
      text: json['text'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
      'text': text,
    };
  }
}

/// Server text chunk message - streaming text from the server.
class ServerTextChunkMsg extends ServerMsgBase {
  final String text;
  final MsgStatus status;

  ServerTextChunkMsg({
    required this.text,
    required this.status,
    required super.timestamp,
  }) : super(type: ServerMsgType.textChunk);

  factory ServerTextChunkMsg.fromJson(Map<String, dynamic> json) {
    return ServerTextChunkMsg(
      text: json['text'] as String? ?? '',
      status: MsgStatus.fromString(json['status'] as String? ?? 'pending'),
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
      'text': text,
      'status': status.value,
    };
  }
}

/// Client text message - send text to the server.
class ClientTextMsg extends ClientMsgBase {
  final String text;

  ClientTextMsg({
    required this.text,
    required super.timestamp,
  }) : super(type: ClientMsgType.text);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'text': text,
    };
  }
}

/// Client text chunk message - streaming text to the server.
class ClientTextChunkMsg extends ClientMsgBase {
  final String text;
  final MsgStatus status;

  ClientTextChunkMsg({
    required this.text,
    required this.status,
    required super.timestamp,
  }) : super(type: ClientMsgType.textChunk);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'text': text,
      'status': status.value,
    };
  }
}

/// Union type for server text messages.
typedef ServerTextMsgType
    = ServerMsgBase; // Can be ServerTextMsg or ServerTextChunkMsg

/// Union type for client text messages.
typedef ClientTextMsgType
    = ClientMsgBase; // Can be ClientTextMsg or ClientTextChunkMsg

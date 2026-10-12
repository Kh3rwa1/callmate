// Base message classes for all SDK messages.

import 'types.dart';

/// Base class for all messages.
abstract class MsgBase {
  final double timestamp;

  MsgBase({required this.timestamp});

  Map<String, dynamic> toJson();
}

/// Base class for all client messages.
abstract class ClientMsgBase extends MsgBase {
  final MsgOrigin origin = MsgOrigin.client;
  final ClientMsgType type;

  ClientMsgBase({
    required this.type,
    required super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
    };
  }
}

/// Base class for all server messages.
abstract class ServerMsgBase extends MsgBase {
  final MsgOrigin origin = MsgOrigin.server;
  final ServerMsgType type;

  ServerMsgBase({
    required this.type,
    required super.timestamp,
  });

  factory ServerMsgBase.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    final type = typeStr != null ? ServerMsgType.fromString(typeStr) : null;

    if (type == null) {
      throw ArgumentError('Unknown server message type: $typeStr');
    }

    // This is a factory that delegates to specific message types
    // The actual parsing happens in parseServerMessage()
    throw UnimplementedError(
      'Use parseServerMessage() to parse server messages',
    );
  }
}

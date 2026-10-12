// System messages for heartbeat and latency measurement.

import 'base.dart';
import 'types.dart';

/// Latency measurement ping from server.
class ServerPingMsg extends ServerMsgBase {
  final int eventId;

  ServerPingMsg({
    required this.eventId,
    required super.timestamp,
  }) : super(type: ServerMsgType.ping);

  factory ServerPingMsg.fromJson(Map<String, dynamic> json) {
    return ServerPingMsg(
      eventId: json['event_id'] as int? ?? 0,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
      'event_id': eventId,
    };
  }
}

/// Response to latency ping.
class ClientPongMsg extends ClientMsgBase {
  final int eventId;

  ClientPongMsg({
    required this.eventId,
    required super.timestamp,
  }) : super(type: ClientMsgType.pong);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'event_id': eventId,
    };
  }
}

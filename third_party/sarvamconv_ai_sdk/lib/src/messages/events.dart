// Event message types from the server.

import 'base.dart';
import 'types.dart';

/// Base class for all server events.
abstract class ServerEventBase extends ServerMsgBase {
  ServerEventBase({
    required super.type,
    required super.timestamp,
  });
}

/// Signals that the user interrupted the agent (e.g., barge-in).
///
/// Clients should stop any ongoing playback immediately.
class ServerUserInterruptEvent extends ServerEventBase {
  ServerUserInterruptEvent({
    required super.timestamp,
  }) : super(type: ServerMsgType.userInterrupt);

  factory ServerUserInterruptEvent.fromJson(Map<String, dynamic> json) {
    return ServerUserInterruptEvent(
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
    };
  }
}

/// Conversation session has ended.
class ServerInteractionEndEvent extends ServerEventBase {
  ServerInteractionEndEvent({
    required super.timestamp,
  }) : super(type: ServerMsgType.interactionEnd);

  factory ServerInteractionEndEvent.fromJson(Map<String, dynamic> json) {
    return ServerInteractionEndEvent(
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
    };
  }
}

/// Conversation session has started/connected.
class ServerInteractionConnectedEvent extends ServerEventBase {
  final String referenceId;
  final String interactionId;
  final Map<String, dynamic>? agentVariables;
  final SarvamToolLanguageName? initialLanguageName;
  final String? initialBotMessage;
  final String? initialStateName;

  ServerInteractionConnectedEvent({
    required this.referenceId,
    required this.interactionId,
    this.agentVariables,
    this.initialLanguageName,
    this.initialBotMessage,
    this.initialStateName,
    required super.timestamp,
  }) : super(type: ServerMsgType.interactionConnected);

  factory ServerInteractionConnectedEvent.fromJson(Map<String, dynamic> json) {
    return ServerInteractionConnectedEvent(
      referenceId: json['reference_id'] as String? ?? '',
      interactionId: json['interaction_id'] as String? ?? '',
      agentVariables: json['agent_variables'] as Map<String, dynamic>?,
      initialLanguageName: json['initial_language_name'] != null
          ? SarvamToolLanguageName.fromString(json['initial_language_name'])
          : null,
      initialBotMessage: json['initial_bot_message'] as String?,
      initialStateName: json['initial_state_name'] as String?,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'origin': origin.value,
      'type': type.value,
      'timestamp': timestamp,
      'reference_id': referenceId,
      'interaction_id': interactionId,
      if (agentVariables != null) 'agent_variables': agentVariables,
      if (initialLanguageName != null)
        'initial_language_name': initialLanguageName!.value,
      if (initialBotMessage != null) 'initial_bot_message': initialBotMessage,
      if (initialStateName != null) 'initial_state_name': initialStateName,
    };
  }
}

/// CallPilot patch: a server event this SDK has no class for yet (for
/// example `server.event.transcription`). Carries the raw message so the
/// app can read what it needs instead of the SDK dropping it.
class ServerRawEvent extends ServerEventBase {
  ServerRawEvent({
    required this.rawType,
    required this.data,
    required super.timestamp,
    super.type = ServerMsgType.unknown,
  });

  /// The message's own `type` string, e.g. `server.event.transcription`.
  final String rawType;
  final Map<String, dynamic> data;

  factory ServerRawEvent.fromJson(Map<String, dynamic> json) {
    final raw = json['type'] as String? ?? '';
    return ServerRawEvent(
      rawType: raw,
      data: json,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
      type: ServerMsgType.fromString(raw) ?? ServerMsgType.unknown,
    );
  }

  @override
  Map<String, dynamic> toJson() => data;
}

// Action messages (client and server).

import 'base.dart';
import 'config.dart';
import 'types.dart';

/// Initialize interaction message from client.
///
/// This is both the configuration object AND
/// the message sent to start an interaction.
class ClientInteractionStartMsg extends ClientMsgBase {
  final Map<String, dynamic>? agentVariables;
  final SarvamToolLanguageName? initialLanguageName;
  final String? initialBotMessage;
  final String? initialStateName;

  ClientInteractionStartMsg({
    this.agentVariables,
    this.initialLanguageName,
    this.initialBotMessage,
    this.initialStateName,
    required super.timestamp,
  }) : super(type: ClientMsgType.interactionStart);

  /// Create an interaction start message from `InteractionConfig`.
  ///
  /// The `timestamp` is set at creation time.
  factory ClientInteractionStartMsg.fromConfig(InteractionConfig config) {
    return ClientInteractionStartMsg(
      agentVariables: config.agentVariables,
      initialLanguageName: config.initialLanguageName,
      initialBotMessage: config.initialBotMessage,
      initialStateName: config.initialStateName,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      if (agentVariables != null) 'agent_variables': agentVariables,
      if (initialLanguageName != null)
        'initial_language_name': initialLanguageName!.value,
      if (initialBotMessage != null) 'initial_bot_message': initialBotMessage,
      if (initialStateName != null) 'initial_state_name': initialStateName,
    };
  }
}

/// Client requesting interaction end.
class ClientInteractionEndMsg extends ClientMsgBase {
  ClientInteractionEndMsg({
    required super.timestamp,
  }) : super(type: ClientMsgType.interactionEnd);
}

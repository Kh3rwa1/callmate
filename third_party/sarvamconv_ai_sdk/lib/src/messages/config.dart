// Configuration classes for interaction setup.

import 'types.dart';

/// Custom app overrides for an interaction.
class CustomAppOverrides {
  final Map<String, dynamic>? agentVariables;
  final SarvamToolLanguageName? initialLanguageName;
  final String? initialBotMessage;
  final String? initialStateName;

  CustomAppOverrides({
    this.agentVariables,
    this.initialLanguageName,
    this.initialBotMessage,
    this.initialStateName,
  });

  Map<String, dynamic> toJson() {
    return {
      if (agentVariables != null) 'agent_variables': agentVariables,
      if (initialLanguageName != null)
        'initial_language_name': initialLanguageName!.value,
      if (initialBotMessage != null) 'initial_bot_message': initialBotMessage,
      if (initialStateName != null) 'initial_state_name': initialStateName,
    };
  }

  factory CustomAppOverrides.fromJson(Map<String, dynamic> json) {
    return CustomAppOverrides(
      agentVariables: json['agent_variables'] as Map<String, dynamic>?,
      initialLanguageName: json['initial_language_name'] != null
          ? SarvamToolLanguageName.fromString(json['initial_language_name'])
          : null,
      initialBotMessage: json['initial_bot_message'] as String?,
      initialStateName: json['initial_state_name'] as String?,
    );
  }
}

/// Configuration used to start an interaction.
///
/// This config is used to build the actual start message
/// (`ClientInteractionStartMsg`) that is sent on connect.
class InteractionConfig extends CustomAppOverrides {
  final UserIdentifierType userIdentifierType;
  final String userIdentifier;
  final String orgId;
  final String workspaceId;
  final String appId;
  final int? version;
  final InteractionType interactionType;
  final int sampleRate;

  InteractionConfig({
    required this.userIdentifierType,
    required this.userIdentifier,
    required this.orgId,
    required this.workspaceId,
    required this.appId,
    this.version,
    required this.interactionType,
    required this.sampleRate,
    super.agentVariables,
    super.initialLanguageName,
    super.initialBotMessage,
    super.initialStateName,
  }) {
    if (!isValidSampleRate(sampleRate)) {
      throw ArgumentError(
        'Sample rate $sampleRate not supported. Supported rates: $supportedSampleRates',
      );
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'user_identifier_type': userIdentifierType.value,
      'user_identifier': userIdentifier,
      'org_id': orgId,
      'workspace_id': workspaceId,
      'app_id': appId,
      if (version != null) 'version': version,
      'interaction_type': interactionType.value,
      'sample_rate': sampleRate,
    };
  }
}

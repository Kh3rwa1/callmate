// Message type enumerations and constants for the Sarvam SDK.

/// Audio encoding formats supported by the SDK.
enum AudioEncoding {
  linear16('audio/wav');

  final String value;
  const AudioEncoding(this.value);
}

/// Supported sample rates for audio.
enum SupportedSampleRate {
  rate8kHz(8000),
  rate16kHz(16000),
  rate48kHz(48000);

  final int value;
  const SupportedSampleRate(this.value);
}

/// List of supported sample rates for validation.
const List<int> supportedSampleRates = [8000, 16000, 48000];

/// Default output sample rate.
const int outputSampleRate = 16000;

/// Validates if a sample rate is supported.
bool isValidSampleRate(int sampleRate) {
  return supportedSampleRates.contains(sampleRate);
}

/// Categories of server messages.
enum ServerMsgCategory {
  media,
  action,
  system,
  event,
}

/// Status of a message stream.
enum MsgStatus {
  pending('pending'),
  completed('completed'),
  failed('failed');

  final String value;
  const MsgStatus(this.value);

  static MsgStatus fromString(String value) {
    return MsgStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MsgStatus.pending,
    );
  }
}

/// Categories of client messages.
enum ClientMsgCategory {
  media,
  action,
  system,
}

/// Origin of a message.
enum MsgOrigin {
  server('server'),
  client('client');

  final String value;
  const MsgOrigin(this.value);
}

/// Types of messages the server can send.
enum ServerMsgType {
  audioChunk('server.media.audio_chunk'),
  audio('server.media.audio'),
  text('server.media.text'),
  textChunk('server.media.text_chunk'),
  ping('server.system.ping'),
  interactionEnd('server.action.interaction_end'),
  interactionConnected('server.action.interaction_connected'),
  userSpeechStart('server.event.user_speech_start'),
  userSpeechEnd('server.event.user_speech_end'),
  userInterrupt('server.event.user_interrupt'),
  variableUpdate('server.event.variable_update'),
  languageChange('server.event.language_change'),
  stateTransition('server.event.state_transition'),
  kbQuery('server.event.kb_query'),
  toolCall('server.event.tool_call'),
  // CallPilot patch: newer servers send live transcripts.
  transcription('server.event.transcription'),
  // CallPilot patch: any type this SDK doesn't know yet.
  unknown('server.unknown');

  final String value;
  const ServerMsgType(this.value);

  static ServerMsgType? fromString(String value) {
    for (final type in ServerMsgType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Types of messages the client can send.
enum ClientMsgType {
  audioChunk('client.media.audio_chunk'),
  text('client.media.text'),
  textChunk('client.media.text_chunk'),
  audio('client.media.audio'),
  interactionStart('client.action.interaction_start'),
  interactionEnd('client.action.interaction_end'),
  variableUpdate('client.action.variable_update'),
  languageChange('client.action.language_change'),
  stateTransition('client.action.state_transition'),
  pong('client.system.pong');

  final String value;
  const ClientMsgType(this.value);
}

/// Type of interaction.
enum InteractionType {
  call('call'),
  chat('chat');

  final String value;
  const InteractionType(this.value);

  static InteractionType fromString(String value) {
    return InteractionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => InteractionType.call,
    );
  }
}

/// Type of user identifier.
enum UserIdentifierType {
  phoneNumber('phone_number'),
  email('email'),
  custom('custom'),
  unknown('unknown');

  final String value;
  const UserIdentifierType(this.value);
}

/// Language names supported by Sarvam tools.
enum SarvamToolLanguageName {
  bengali('Bengali'),
  gujarati('Gujarati'),
  kannada('Kannada'),
  malayalam('Malayalam'),
  tamil('Tamil'),
  telugu('Telugu'),
  punjabi('Punjabi'),
  odia('Odia'),
  marathi('Marathi'),
  hindi('Hindi'),
  english('English');

  final String value;
  const SarvamToolLanguageName(this.value);

  static SarvamToolLanguageName? fromString(String value) {
    for (final lang in SarvamToolLanguageName.values) {
      if (lang.value == value) return lang;
    }
    return null;
  }
}

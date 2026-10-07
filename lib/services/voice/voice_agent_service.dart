import 'dart:async';
import 'dart:typed_data';

/// Vendor-neutral voice agent contract. The UI only ever sees this.
enum VoiceConnectionState {
  idle,
  connecting,
  listening,
  speaking,
  thinking,
  disconnected,
  error,
}

class VoiceTranscriptEntry {
  const VoiceTranscriptEntry({
    required this.id,
    required this.isAgent,
    required this.text,
    this.isFinal = true,
  });
  final String id;
  final bool isAgent;
  final String text;
  final bool isFinal;

  VoiceTranscriptEntry copyWith({String? text, bool? isFinal}) =>
      VoiceTranscriptEntry(
        id: id,
        isAgent: isAgent,
        text: text ?? this.text,
        isFinal: isFinal ?? this.isFinal,
      );
}

class VoiceAgentException implements Exception {
  const VoiceAgentException(this.message, {this.permissionDenied = false});
  final String message;
  final bool permissionDenied;
  @override
  String toString() => message;
}

abstract class VoiceAgentService {
  /// Starts a test conversation with the owner's AI employee.
  Future<void> startTestSession({
    Map<String, dynamic> agentVariables = const {},
  });

  /// Ends the session and releases mic/audio/socket. Safe to call repeatedly.
  Future<void> stopSession();

  /// Push raw PCM16 audio (only needed when NOT using the built-in mic pipeline).
  Future<void> sendAudio(Uint8List pcm16);

  /// Optional text input (useful for accessibility & noisy environments).
  Future<void> sendText(String text);

  Future<void> setMuted(bool muted);

  /// Full transcript snapshot each time anything changes.
  Stream<List<VoiceTranscriptEntry>> getTranscriptStream();

  Stream<VoiceConnectionState> getConnectionState();

  VoiceConnectionState get currentState;

  /// 0..1 rough audio activity, for the waveform.
  Stream<double> get levelStream;

  bool get isMuted;

  Future<void> dispose();
}

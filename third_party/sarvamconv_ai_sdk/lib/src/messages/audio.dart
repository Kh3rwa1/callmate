// Audio message types for streaming audio data.

import 'dart:convert';
import 'dart:typed_data';

import 'base.dart';
import 'types.dart';

/// Client audio chunk message - sends audio data to the server.
class ClientAudioChunkMsg extends ClientMsgBase {
  final String audioBase64;
  final AudioEncoding format;
  final int sampleRate;

  ClientAudioChunkMsg({
    required this.audioBase64,
    required this.format,
    required this.sampleRate,
    required super.timestamp,
  }) : super(type: ClientMsgType.audioChunk);

  /// Create from raw audio bytes.
  factory ClientAudioChunkMsg.fromBytes({
    required Uint8List audioData,
    required AudioEncoding format,
    required int sampleRate,
    required double timestamp,
  }) {
    return ClientAudioChunkMsg(
      audioBase64: base64Encode(audioData),
      format: format,
      sampleRate: sampleRate,
      timestamp: timestamp,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'audio_base64': audioBase64,
      'format': format.value,
      'sample_rate': sampleRate,
    };
  }
}

/// Client audio message - sends complete audio data for transcription.
class ClientAudioMsg extends ClientMsgBase {
  final String audioBase64;
  final AudioEncoding format;
  final int sampleRate;
  final bool transcribe;

  ClientAudioMsg({
    required this.audioBase64,
    required this.format,
    required this.sampleRate,
    this.transcribe = false,
    required super.timestamp,
  }) : super(type: ClientMsgType.audio);

  /// Create from raw audio bytes.
  factory ClientAudioMsg.fromBytes({
    required Uint8List audioData,
    required AudioEncoding format,
    required int sampleRate,
    bool transcribe = false,
    required double timestamp,
  }) {
    return ClientAudioMsg(
      audioBase64: base64Encode(audioData),
      format: format,
      sampleRate: sampleRate,
      transcribe: transcribe,
      timestamp: timestamp,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'audio_base64': audioBase64,
      'format': format.value,
      'sample_rate': sampleRate,
      'transcribe': transcribe,
    };
  }
}

/// Server audio chunk message - receives audio data from the server.
class ServerAudioChunkMsg extends ServerMsgBase {
  final String audioBase64;
  final AudioEncoding format;
  final int? sampleRate;
  final MsgStatus status;

  ServerAudioChunkMsg({
    required this.audioBase64,
    required this.format,
    this.sampleRate,
    required this.status,
    required super.timestamp,
  }) : super(type: ServerMsgType.audioChunk);

  /// Get the audio data as bytes.
  Uint8List get audioBytes {
    if (audioBase64.isEmpty) return Uint8List(0);
    return base64Decode(audioBase64);
  }

  factory ServerAudioChunkMsg.fromJson(Map<String, dynamic> json) {
    return ServerAudioChunkMsg(
      audioBase64: json['audio_base64'] as String? ?? '',
      format: AudioEncoding.linear16,
      sampleRate: json['sample_rate'] as int?,
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
      'audio_base64': audioBase64,
      'format': format.value,
      if (sampleRate != null) 'sample_rate': sampleRate,
      'status': status.value,
    };
  }
}

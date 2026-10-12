// Audio interface abstractions for handling audio input and output.

import 'dart:typed_data';

/// Callback type for receiving audio input data.
typedef AudioInputCallback = Future<void> Function(
    Uint8List audioData, int frameCount);

/// Abstract audio interface for handling audio input and output.
///
/// Use this interface with [SamvaadAgent] for handling real-time audio.
abstract class AudioInterface {
  /// Starts the audio interface.
  ///
  /// Called one time before the conversation starts.
  /// The [inputCallback] should be called regularly with input audio chunks from
  /// the user. The audio should be in 16-bit PCM mono format. Recommended
  /// chunk size is around 20 milliseconds.
  ///
  /// [inputCallback] - Callback to send audio chunks to the server.
  ///   Takes audio data (Uint8List) and frame count (int) as parameters.
  ///   This callback is provided by the SamvaadAgent.
  Future<void> start(AudioInputCallback inputCallback);

  /// Stops the audio interface.
  ///
  /// Called one time after the conversation ends. Should clean up any resources
  /// used by the audio interface and stop any audio streams. Do not call the
  /// [inputCallback] from [start] after this method is called.
  Future<void> stop();

  /// Output audio to the user.
  ///
  /// The [audio] input is in 16-bit PCM mono format. Implementations can
  /// choose to do additional buffering. This method should return quickly and must
  /// not block.
  ///
  /// [audio] - Audio data in 16-bit PCM mono format
  /// [sampleRate] - Sample rate of the audio in Hz (e.g., 16000, 8000)
  Future<void> output(Uint8List audio, {int? sampleRate});

  /// Interruption signal to stop any audio output.
  ///
  /// User has interrupted the agent and all previously buffered audio output should
  /// be stopped.
  void interrupt();
}

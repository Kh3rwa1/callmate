// Default audio interface implementation.
//
// Uses platform-specific audio:
// - iOS: flutter_sound streaming
// - Android: Native AudioTrack via method channel

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_interface.dart';

/// Default audio interface with platform-specific audio output.
class DefaultAudioInterface implements AudioInterface {
  final int inputSampleRate;
  final double inputFrameBufferDurationMs;
  final int outputSampleRate;

  // Recording (same for both platforms)
  final AudioRecorder _recorder = AudioRecorder();
  AudioInputCallback? _inputCallback;
  StreamSubscription<Uint8List>? _recordingSubscription;
  int _inputFrameCount = 0;

  // iOS - flutter_sound streaming
  FlutterSoundPlayer? _iosPlayer;
  bool _iosStreamStarted = false;

  // Android - native method channel
  static const _androidChannel = MethodChannel('com.sarvam.audio/playback');
  bool _androidInitialized = false;

  bool _shouldStop = false;
  int _currentOutputSampleRate = 16000;

  DefaultAudioInterface({
    this.inputSampleRate = 16000,
    this.inputFrameBufferDurationMs = 20,
    this.outputSampleRate = 16000,
  }) {
    _currentOutputSampleRate = outputSampleRate;
  }

  @override
  Future<void> start(AudioInputCallback inputCallback) async {
    print('[AudioInterface] Starting...');
    _inputCallback = inputCallback;
    _shouldStop = false;
    _inputFrameCount = 0;

    final status = await Permission.microphone.request();
    print('[AudioInterface] Mic permission: $status');
    if (!status.isGranted) {
      throw Exception('Microphone permission not granted');
    }

    if (!await _recorder.hasPermission()) {
      throw Exception('Recording permission not available');
    }

    // Initialize platform-specific player
    if (Platform.isIOS) {
      await _initIOSPlayer();
    } else if (Platform.isAndroid) {
      await _initAndroidPlayer();
    }
    print('[AudioInterface] Player initialized');

    // Start recording
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: inputSampleRate,
      numChannels: 1,
      bitRate: inputSampleRate * 16,
    );

    print('[AudioInterface] Starting recording stream...');
    final stream = await _recorder.startStream(config);
    print('[AudioInterface] Recording stream started');

    _recordingSubscription = stream.listen(
      (data) {
        if (_inputCallback != null && !_shouldStop) {
          _inputFrameCount++;
          if (_inputFrameCount % 50 == 0) {
            print(
                '[AudioInterface] Sending audio frame $_inputFrameCount, ${data.length} bytes');
          }
          // Fire and forget - don't block the recording stream
          _inputCallback!(data, _inputFrameCount).catchError((e) {
            print('[AudioInterface] Callback error: $e');
          });
        }
      },
      onError: (error) {
        print('[AudioInterface] Recording error: $error');
      },
    );
    print('[AudioInterface] Recording subscription active');
  }

  // === iOS Implementation (flutter_sound streaming) ===

  Future<void> _initIOSPlayer() async {
    _iosPlayer = FlutterSoundPlayer();
    await _iosPlayer!.openPlayer();
    await _startIOSStream();
  }

  Future<void> _startIOSStream() async {
    if (_iosStreamStarted || _iosPlayer == null) return;

    try {
      await _iosPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: _currentOutputSampleRate,
        bufferSize: 4096,
        interleaved: true,
      );
      _iosStreamStarted = true;
    } catch (e) {
      print('[iOS Audio] Stream start error: $e');
    }
  }

  Future<void> _feedIOS(Uint8List audio) async {
    if (!_iosStreamStarted || _iosPlayer == null) return;
    try {
      await _iosPlayer!.feedFromStream(audio);
    } catch (e) {
      print('[iOS Audio] Feed error: $e');
    }
  }

  // === Android Implementation (native AudioTrack) ===

  Future<void> _initAndroidPlayer() async {
    try {
      await _androidChannel.invokeMethod('init', {
        'sampleRate': _currentOutputSampleRate,
      });
      _androidInitialized = true;
      print('[Android Audio] Native AudioTrack initialized');
    } catch (e) {
      print('[Android Audio] Init error: $e');
    }
  }

  Future<void> _feedAndroid(Uint8List audio) async {
    if (!_androidInitialized) return;
    try {
      await _androidChannel.invokeMethod('play', {
        'audioData': audio,
      });
    } catch (e) {
      print('[Android Audio] Play error: $e');
    }
  }

  // === Interface Methods ===

  @override
  Future<void> output(Uint8List audio, {int? sampleRate}) async {
    if (_shouldStop || audio.isEmpty) return;

    final rate = sampleRate ?? outputSampleRate;

    // Handle sample rate change
    if (rate != _currentOutputSampleRate) {
      _currentOutputSampleRate = rate;
      if (Platform.isIOS && _iosStreamStarted) {
        await _iosPlayer?.stopPlayer();
        _iosStreamStarted = false;
        await _startIOSStream();
      } else if (Platform.isAndroid) {
        await _initAndroidPlayer();
      }
    }

    // Feed to platform-specific player
    if (Platform.isIOS) {
      await _feedIOS(audio);
    } else if (Platform.isAndroid) {
      await _feedAndroid(audio);
    }
  }

  @override
  void interrupt() {
    if (Platform.isIOS) {
      if (_iosStreamStarted) {
        _iosPlayer?.stopPlayer();
        _iosStreamStarted = false;
        _startIOSStream();
      }
    } else if (Platform.isAndroid) {
      _androidChannel.invokeMethod('stop');
    }
  }

  @override
  Future<void> stop() async {
    _shouldStop = true;

    await _recordingSubscription?.cancel();
    _recordingSubscription = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}

    // iOS cleanup
    if (_iosPlayer != null) {
      try {
        if (_iosStreamStarted) {
          await _iosPlayer!.stopPlayer();
        }
        await _iosPlayer!.closePlayer();
      } catch (_) {}
      _iosPlayer = null;
      _iosStreamStarted = false;
    }

    // Android cleanup
    if (_androidInitialized) {
      try {
        await _androidChannel.invokeMethod('dispose');
      } catch (_) {}
      _androidInitialized = false;
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}

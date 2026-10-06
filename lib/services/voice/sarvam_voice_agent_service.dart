import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sarvamconv_ai_sdk/sarvamconv_ai_sdk.dart';

import '../../data/models/misc.dart';
import '../../data/repositories/repositories.dart';
import 'voice_agent_service.dart';

/// Real in-app voice using the official `sarvamconv_ai_sdk` (v1.0.x).
///
/// SECURITY: no Sarvam API key is ever passed. We follow Sarvam's documented
/// proxy pattern: `SamvaadAgent(baseUrl: <our proxy>, headers: {Authorization})`.
/// Our backend validates the short-lived session token and injects X-API-Key.
///
/// Only SDK APIs present in the installed package are used:
/// SamvaadAgent(config, audioInterface, textCallback, eventCallback, baseUrl, headers),
/// start(), waitForConnect(), stop(), sendAudio(), sendText(), isConnected,
/// DefaultAudioInterface, InteractionConfig, ServerTextChunkMsg/ServerTextMsg,
/// ServerInteractionConnectedEvent / ServerInteractionEndEvent / ServerUserInterruptEvent.
class SarvamVoiceAgentService implements VoiceAgentService {
  SarvamVoiceAgentService(this._sessions);

  final VoiceSessionRepository _sessions;

  SamvaadAgent? _agent;
  _MutableAudioInterface? _audio;
  final _state = StreamController<VoiceConnectionState>.broadcast();
  final _transcript = StreamController<List<VoiceTranscriptEntry>>.broadcast();
  final _level = StreamController<double>.broadcast();
  final List<VoiceTranscriptEntry> _entries = [];
  VoiceConnectionState _current = VoiceConnectionState.idle;
  Timer? _speakingDecay;
  bool _muted = false;
  int _seq = 0;

  @override
  VoiceConnectionState get currentState => _current;
  @override
  bool get isMuted => _muted;

  void _set(VoiceConnectionState s) {
    if (_current == s) return;
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  void _emit() {
    if (!_transcript.isClosed) _transcript.add(List.unmodifiable(_entries));
  }

  @override
  Future<void> startTestSession({Map<String, dynamic> agentVariables = const {}}) async {
    if (_agent != null) return;
    if (kIsWeb) {
      throw const VoiceAgentException('Live voice runs on the Android & iOS app. Use demo mode in the browser.');
    }
    _set(VoiceConnectionState.connecting);

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _set(VoiceConnectionState.error);
      throw const VoiceAgentException('Microphone access is needed to talk to your AI employee.', permissionDenied: true);
    }

    final VoiceTestSession session;
    try {
      session = await _sessions.createTestSession();
    } catch (_) {
      _set(VoiceConnectionState.error);
      throw const VoiceAgentException("Riya couldn't connect. Check your connection and try again.");
    }

    final config = InteractionConfig(
      orgId: session.orgId,
      workspaceId: session.workspaceId,
      appId: session.appId,
      version: session.version,
      userIdentifier: session.userIdentifier,
      userIdentifierType: UserIdentifierType.custom,
      interactionType: InteractionType.call,
      sampleRate: 16000,
      agentVariables: {...session.agentVariables, ...agentVariables},
    );

    _audio = _MutableAudioInterface(DefaultAudioInterface(inputSampleRate: 16000), onOutput: _onAgentAudio);
    _agent = SamvaadAgent(
      config: config,
      baseUrl: session.proxyBaseUrl,
      headers: {'Authorization': 'Bearer ${session.sessionToken}'},
      audioInterface: _audio,
      textCallback: _onText,
      eventCallback: _onEvent,
    );

    try {
      await _agent!.start();
      final ok = await _agent!.waitForConnect(timeout: const Duration(seconds: 12));
      if (!ok) throw const VoiceAgentException('timeout');
      _set(VoiceConnectionState.listening);
      unawaited(
        _agent!.waitForDisconnect().then((_) {
          if (_agent != null) {
            _teardown(VoiceConnectionState.disconnected);
          }
        }),
      );
    } catch (_) {
      await _teardown(VoiceConnectionState.error);
      throw const VoiceAgentException("Riya couldn't connect. Check your connection and try again.");
    }
  }

  Future<void> _onText(ServerMsgBase msg) async {
    if (msg is ServerTextChunkMsg) {
      final last = _entries.isNotEmpty ? _entries.last : null;
      if (last != null && last.isAgent && !last.isFinal) {
        _entries[_entries.length - 1] = last.copyWith(text: last.text + msg.text, isFinal: msg.status == MsgStatus.completed);
      } else {
        _entries.add(VoiceTranscriptEntry(id: 'a${_seq++}', isAgent: true, text: msg.text, isFinal: msg.status == MsgStatus.completed));
      }
      _emit();
    } else if (msg is ServerTextMsg) {
      _entries.add(VoiceTranscriptEntry(id: 'a${_seq++}', isAgent: true, text: msg.text));
      _emit();
    }
  }

  Future<void> _onEvent(ServerEventBase e) async {
    if (e is ServerInteractionConnectedEvent) {
      final greet = e.initialBotMessage;
      if (greet != null && greet.isNotEmpty) {
        _entries.add(VoiceTranscriptEntry(id: 'a${_seq++}', isAgent: true, text: greet));
        _emit();
      }
      _set(VoiceConnectionState.listening);
    } else if (e is ServerUserInterruptEvent) {
      _set(VoiceConnectionState.listening);
    } else if (e is ServerInteractionEndEvent) {
      await _teardown(VoiceConnectionState.disconnected);
    }
  }

  void _onAgentAudio(Uint8List pcm) {
    _set(VoiceConnectionState.speaking);
    if (!_level.isClosed) _level.add(_rms(pcm));
    _speakingDecay?.cancel();
    _speakingDecay = Timer(const Duration(milliseconds: 700), () {
      if (_current == VoiceConnectionState.speaking) _set(VoiceConnectionState.listening);
      if (!_level.isClosed) _level.add(0);
    });
  }

  static double _rms(Uint8List b) {
    if (b.length < 4) return 0;
    final data = ByteData.sublistView(b);
    var sum = 0.0;
    final n = b.length ~/ 2;
    for (var i = 0; i < n; i += 4) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += s * s;
    }
    return min(1, sqrt(sum / (n / 4)) * 3.2);
  }

  @override
  Future<void> sendAudio(Uint8List pcm16) async {
    if (_muted) return;
    await _agent?.sendAudio(pcm16);
  }

  @override
  Future<void> sendText(String text) async {
    if (_agent == null || text.trim().isEmpty) return;
    _entries.add(VoiceTranscriptEntry(id: 'u${_seq++}', isAgent: false, text: text.trim()));
    _emit();
    _set(VoiceConnectionState.thinking);
    await _agent!.sendText(text.trim());
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    _audio?.muted = muted;
  }

  Future<void> _teardown(VoiceConnectionState end) async {
    final a = _agent;
    _agent = null;
    _speakingDecay?.cancel();
    try {
      await a?.stop();
    } catch (_) {}
    try {
      await _audio?.inner.dispose();
    } catch (_) {}
    _audio = null;
    _set(end);
  }

  @override
  Future<void> stopSession() => _teardown(VoiceConnectionState.disconnected);

  @override
  Stream<List<VoiceTranscriptEntry>> getTranscriptStream() => _transcript.stream;

  @override
  Stream<VoiceConnectionState> getConnectionState() => _state.stream;

  @override
  Stream<double> get levelStream => _level.stream;

  @override
  Future<void> dispose() async {
    await stopSession();
    await _state.close();
    await _transcript.close();
    await _level.close();
  }
}

/// Wraps the SDK's DefaultAudioInterface to support mute + level metering
/// without depending on SDK internals.
class _MutableAudioInterface implements AudioInterface {
  _MutableAudioInterface(this.inner, {required this.onOutput});
  final DefaultAudioInterface inner;
  final void Function(Uint8List) onOutput;
  bool muted = false;

  @override
  Future<void> start(AudioInputCallback inputCallback) => inner.start((data, frames) async {
    if (muted) return;
    await inputCallback(data, frames);
  });

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> output(Uint8List audio, {int? sampleRate}) {
    onOutput(audio);
    return inner.output(audio, sampleRate: sampleRate);
  }

  @override
  void interrupt() => inner.interrupt();
}

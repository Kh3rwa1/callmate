import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sarvamconv_ai_sdk/sarvamconv_ai_sdk.dart';

import '../../core/config/app_env.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/misc.dart';
import '../../data/repositories/repositories.dart';
import 'speech/speech_interop.dart';
import 'voice_agent_service.dart';

/// Real in-app voice using the official `sarvamconv_ai_sdk` (v1.0.x).
///
/// Always connects through OUR backend's Sarvam proxy using the short-lived
/// session token from `/voice/test-session`. The client never holds a Sarvam
/// API key; the backend injects it server-side.
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
  String? _conversationId;
  final List<Timer> _webTimers = [];
  Timer? _webLevelTimer;
  final Random _rnd = Random();

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

  void _stopWebTimers() {
    for (final t in _webTimers) {
      t.cancel();
    }
    _webTimers.clear();
    _webLevelTimer?.cancel();
    _webLevelTimer = null;
    if (!_level.isClosed) _level.add(0);
  }

  void _startWebLevel({required bool speaking}) {
    _webLevelTimer?.cancel();
    _webLevelTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (_level.isClosed) return;
      _level.add(
        speaking ? 0.35 + _rnd.nextDouble() * 0.55 : _rnd.nextDouble() * 0.18,
      );
    });
  }

  Future<void> _startWebSession({
    Map<String, dynamic> agentVariables = const {},
  }) async {
    _conversationId = null;
    _stopWebTimers();
    _entries.clear();
    _emit();
    _set(VoiceConnectionState.connecting);

    VoiceTestSession? session;
    try {
      session = await _sessions.createTestSession();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SarvamVoiceAgent] Web test session error: $e');
      }
    }

    final agentName =
        agentVariables['agent_name'] ??
        session?.agentVariables['agent_name'] ??
        'Your AI Assistant';
    final bizName =
        agentVariables['business_name'] ??
        session?.agentVariables['business_name'] ??
        'your business';

    await Future<void>.delayed(const Duration(milliseconds: 600));
    _set(VoiceConnectionState.speaking);
    _startWebLevel(speaking: true);

    final greeting =
        session?.greetingText ??
        "Hello, I'm $agentName, an AI assistant from $bizName. How can I assist you today?";
    _entries.add(
      VoiceTranscriptEntry(
        id: 'web_agent_1',
        isAgent: true,
        text: greeting,
        isFinal: true,
      ),
    );
    _emit();
    if (session?.greetingAudioBase64 != null &&
        session!.greetingAudioBase64!.isNotEmpty) {
      playBase64Audio(session.greetingAudioBase64!);
    } else {
      speakAgentText(greeting);
    }

    _webTimers.add(
      Timer(const Duration(milliseconds: 2800), () {
        if (_current != VoiceConnectionState.speaking) return;
        _set(VoiceConnectionState.listening);
        _startWebLevel(speaking: false);
      }),
    );
  }

  @override
  Future<void> startTestSession({
    Map<String, dynamic> agentVariables = const {},
  }) async {
    if (_agent != null) return;
    if (kIsWeb) {
      await _startWebSession(agentVariables: agentVariables);
      return;
    }
    _set(VoiceConnectionState.connecting);

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _set(VoiceConnectionState.error);
      throw const VoiceAgentException(
        'Microphone access is needed to talk to your AI employee.',
        permissionDenied: true,
      );
    }

    final VoiceTestSession session;
    try {
      session = await _sessions.createTestSession();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SarvamVoiceAgent] Server session creation error: $e');
      }
      _set(VoiceConnectionState.error);
      throw VoiceAgentException(
        "Your AI employee couldn't connect to the backend. ${friendlyError(e)}",
      );
    }
    if (session.sessionToken.isEmpty) {
      _set(VoiceConnectionState.error);
      throw const VoiceAgentException(
        "Your AI employee couldn't start a secure voice session. Please try again.",
      );
    }

    final proxyBaseUrl = resolveSarvamProxyBaseUrl(session.proxyBaseUrl);

    final config = InteractionConfig(
      orgId: session.orgId,
      workspaceId: session.workspaceId,
      appId: session.appId,
      version: session.version,
      userIdentifier: session.userIdentifier,
      userIdentifierType: UserIdentifierType.custom,
      interactionType: InteractionType.call,
      sampleRate: 16000,
      agentVariables: {
        'gender': 'female',
        'voice': 'female',
        'speaker': 'meera',
        'tts_model': 'bulbul:v4-flash',
        ...session.agentVariables,
        ...agentVariables,
      },
    );

    final headers = {'Authorization': 'Bearer ${session.sessionToken}'};

    _audio = _MutableAudioInterface(
      DefaultAudioInterface(inputSampleRate: 16000),
      onOutput: _onAgentAudio,
    );
    _agent = SamvaadAgent(
      config: config,
      baseUrl: proxyBaseUrl,
      headers: headers,
      audioInterface: _audio,
      textCallback: _onText,
      eventCallback: _onEvent,
    );

    try {
      await _agent!.start();
      final ok = await _agent!.waitForConnect(
        timeout: const Duration(seconds: 15),
      );
      if (!ok) {
        throw const VoiceAgentException(
          'Connection to Sarvam AI timed out. Please try again.',
        );
      }
      _set(VoiceConnectionState.listening);
      unawaited(
        _agent!.waitForDisconnect().then((_) {
          if (_agent != null) {
            _teardown(VoiceConnectionState.disconnected);
          }
        }),
      );
    } catch (err) {
      if (kDebugMode) debugPrint('[SarvamVoiceAgent] Failed to connect: $err');
      await _teardown(VoiceConnectionState.error);
      throw VoiceAgentException(
        "Sarvam voice connection error: ${friendlyError(err)}",
      );
    }
  }

  Future<void> _onText(ServerMsgBase msg) async {
    if (msg is ServerTextChunkMsg) {
      final last = _entries.isNotEmpty ? _entries.last : null;
      if (last != null && last.isAgent && !last.isFinal) {
        _entries[_entries.length - 1] = last.copyWith(
          text: last.text + msg.text,
          isFinal: msg.status == MsgStatus.completed,
        );
      } else {
        _entries.add(
          VoiceTranscriptEntry(
            id: 'a${_seq++}',
            isAgent: true,
            text: msg.text,
            isFinal: msg.status == MsgStatus.completed,
          ),
        );
      }
      _emit();
    } else if (msg is ServerTextMsg) {
      _entries.add(
        VoiceTranscriptEntry(id: 'a${_seq++}', isAgent: true, text: msg.text),
      );
      _emit();
    }
  }

  Future<void> _onEvent(ServerEventBase e) async {
    if (e is ServerInteractionConnectedEvent) {
      final greet = e.initialBotMessage;
      if (greet != null && greet.isNotEmpty) {
        _entries.add(
          VoiceTranscriptEntry(id: 'a${_seq++}', isAgent: true, text: greet),
        );
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
      if (_current == VoiceConnectionState.speaking) {
        _set(VoiceConnectionState.listening);
      }
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
    final clean = text.trim();
    if (clean.isEmpty) return;

    if (kIsWeb) {
      _entries.add(
        VoiceTranscriptEntry(id: 'u${_seq++}', isAgent: false, text: clean),
      );
      _emit();
      _set(VoiceConnectionState.thinking);
      _startWebLevel(speaking: false);

      try {
        final chatReply = await _sessions.sendChatMessage(
          clean,
          conversationId: _conversationId,
        );
        if (chatReply.conversationId != null) {
          _conversationId = chatReply.conversationId;
        }
        if (_current == VoiceConnectionState.disconnected ||
            _current == VoiceConnectionState.idle) {
          return;
        }
        _entries.add(
          VoiceTranscriptEntry(
            id: 'a${_seq++}',
            isAgent: true,
            text: chatReply.reply,
          ),
        );
        _emit();
        _set(VoiceConnectionState.speaking);
        _startWebLevel(speaking: true);
        if (chatReply.audioBase64 != null &&
            chatReply.audioBase64!.isNotEmpty) {
          playBase64Audio(chatReply.audioBase64!);
        } else {
          speakAgentText(chatReply.reply);
        }
        _webTimers.add(
          Timer(
            Duration(
              milliseconds: min(8000, max(2200, chatReply.reply.length * 50)),
            ),
            () {
              if (_current == VoiceConnectionState.speaking) {
                _set(VoiceConnectionState.listening);
                _startWebLevel(speaking: false);
              }
            },
          ),
        );
      } catch (err) {
        if (kDebugMode) debugPrint('[SarvamVoiceAgent] Web chat error: $err');
        _set(VoiceConnectionState.listening);
      }
      return;
    }

    if (_agent == null) return;
    _entries.add(
      VoiceTranscriptEntry(id: 'u${_seq++}', isAgent: false, text: clean),
    );
    _emit();
    _set(VoiceConnectionState.thinking);
    await _agent!.sendText(clean);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    _audio?.muted = muted;
  }

  Future<void> _teardown(VoiceConnectionState end) async {
    _conversationId = null;
    _stopWebTimers();
    stopAgentSpeech();
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
  Stream<List<VoiceTranscriptEntry>> getTranscriptStream() =>
      _transcript.stream;

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

/// Resolves the base URL the Sarvam SDK should talk to.
///
/// Uses the backend-provided [sessionProxyBaseUrl] when present, otherwise
/// falls back to [apiBaseUrl] + [proxyPath] (`SARVAM_PROXY_PATH`). It never
/// points at Sarvam directly. The result always ends with `/`.
String resolveSarvamProxyBaseUrl(
  String sessionProxyBaseUrl, {
  String? apiBaseUrl,
  String proxyPath = AppEnv.sarvamProxyPath,
}) {
  var url = sessionProxyBaseUrl.trim();
  if (url.isEmpty) {
    final base = (apiBaseUrl ?? AppEnv.effectiveApiBaseUrl).replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final path = proxyPath.startsWith('/') ? proxyPath : '/$proxyPath';
    url = '$base$path';
  }
  return url.endsWith('/') ? url : '$url/';
}

/// Wraps the SDK's DefaultAudioInterface to support mute + level metering
/// without depending on SDK internals.
class _MutableAudioInterface implements AudioInterface {
  _MutableAudioInterface(this.inner, {required this.onOutput});
  final DefaultAudioInterface inner;
  final void Function(Uint8List) onOutput;
  bool muted = false;

  @override
  Future<void> start(AudioInputCallback inputCallback) =>
      inner.start((data, frames) async {
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

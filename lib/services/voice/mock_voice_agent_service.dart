import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'voice_agent_service.dart';

/// Scripted demo conversation. The owner plays a parent/student; Riya
/// demonstrates qualification, FAQ answering and callback booking.
class MockVoiceAgentService implements VoiceAgentService {
  MockVoiceAgentService({required this.agentName, required this.businessName, this.failFirstAttempt = false});

  final String agentName;
  final String businessName;
  final bool failFirstAttempt;

  final _state = StreamController<VoiceConnectionState>.broadcast();
  final _transcript = StreamController<List<VoiceTranscriptEntry>>.broadcast();
  final _level = StreamController<double>.broadcast();
  final List<VoiceTranscriptEntry> _entries = [];
  VoiceConnectionState _current = VoiceConnectionState.idle;
  final _timers = <Timer>[];
  Timer? _levelTimer;
  bool _muted = false;
  bool _running = false;
  int _attempts = 0;
  int _seq = 0;
  final _rnd = Random();

  @override
  VoiceConnectionState get currentState => _current;
  @override
  bool get isMuted => _muted;

  void _set(VoiceConnectionState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
    _levelTimer?.cancel();
    if (s == VoiceConnectionState.speaking || (s == VoiceConnectionState.listening && !_muted)) {
      final speaking = s == VoiceConnectionState.speaking;
      _levelTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (_level.isClosed) return;
        _level.add(speaking ? 0.35 + _rnd.nextDouble() * 0.6 : _rnd.nextDouble() * 0.22);
      });
    } else if (!_level.isClosed) {
      _level.add(0);
    }
  }

  void _emit() {
    if (!_transcript.isClosed) _transcript.add(List.unmodifiable(_entries));
  }

  List<(bool, String)> get _script => [
    (true, 'Namaste! I\'m $agentName, the AI admissions assistant at $businessName. Are you enquiring for yourself or for your child?'),
    (false, 'For my son. He wants to prepare for NEET.'),
    (true, 'Wonderful! We have NEET morning, evening and weekend batches. Which timing suits him best?'),
    (false, 'Evening would be better. What are the fees?'),
    (true, 'The NEET evening batch is ₹52,000 per year, payable in three easy instalments. The new batch starts next month.'),
    (false, 'Okay. I\'ll need to discuss with my husband once.'),
    (true, 'Of course! Shall I ask our counsellor to call you tomorrow at 6 PM? I\'ll also send the details on WhatsApp.'),
    (false, 'Yes, that works.'),
    (true, 'Perfect – callback booked for tomorrow, 6 PM. Thank you, and best wishes to your son! 🙏'),
  ];

  void _at(int ms, void Function() f) => _timers.add(
    Timer(Duration(milliseconds: ms), () {
      if (_running) f();
    }),
  );

  @override
  Future<void> startTestSession({Map<String, dynamic> agentVariables = const {}}) async {
    if (_running) return;
    _attempts++;
    _running = true;
    _entries.clear();
    _emit();
    _set(VoiceConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!_running) return;
    if (failFirstAttempt && _attempts == 1) {
      _running = false;
      _set(VoiceConnectionState.error);
      throw const VoiceAgentException("Riya couldn't connect. Check your connection and try again.");
    }
    var t = 0;
    for (final (isAgent, text) in _script) {
      if (isAgent) {
        _at(t, () => _set(VoiceConnectionState.speaking));
        _streamWords(t, text, true);
        t += 380 + text.length * 34;
        _at(t, () => _set(VoiceConnectionState.listening));
        t += 900;
      } else {
        _streamWords(t, text, false);
        t += 300 + text.length * 30;
        _at(t, () => _set(VoiceConnectionState.thinking));
        t += 800;
      }
    }
    _at(t + 600, () {
      _running = false;
      _set(VoiceConnectionState.disconnected);
    });
  }

  void _streamWords(int startMs, String text, bool isAgent) {
    final words = text.split(' ');
    final id = '${isAgent ? 'a' : 'u'}${_seq++}';
    var t = startMs;
    for (var i = 0; i < words.length; i++) {
      final partial = words.take(i + 1).join(' ');
      final done = i == words.length - 1;
      _at(t, () {
        final idx = _entries.indexWhere((e) => e.id == id);
        final entry = VoiceTranscriptEntry(id: id, isAgent: isAgent, text: partial, isFinal: done);
        if (idx < 0) {
          _entries.add(entry);
        } else {
          _entries[idx] = entry;
        }
        _emit();
      });
      t += isAgent ? 150 : 140;
    }
  }

  @override
  Future<void> stopSession() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _levelTimer?.cancel();
    if (_running || _current != VoiceConnectionState.idle) {
      _running = false;
      _set(VoiceConnectionState.disconnected);
    }
  }

  @override
  Future<void> sendAudio(Uint8List pcm16) async {}

  @override
  Future<void> sendText(String text) async {
    if (!_running) return;
    _entries.add(VoiceTranscriptEntry(id: 'u${_seq++}', isAgent: false, text: text));
    _emit();
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (_current == VoiceConnectionState.listening) _set(VoiceConnectionState.listening);
  }

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

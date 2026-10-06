import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../services/voice/voice_agent_service.dart';
import '../calls/transcript_view.dart';

/// "Talk to {employee}" – owner tests their AI employee in-app.
///
/// Session is cleaned up on: leaving the screen, dispose, app backgrounding,
/// call end and connection failure.
class VoiceTestScreen extends ConsumerStatefulWidget {
  const VoiceTestScreen({super.key, this.fromOnboarding = false});
  final bool fromOnboarding;
  @override
  ConsumerState<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends ConsumerState<VoiceTestScreen> with WidgetsBindingObserver {
  late final VoiceAgentService _voice = ref.read(voiceAgentServiceProvider);
  final _subs = <StreamSubscription<dynamic>>[];
  final _scroll = ScrollController();
  VoiceConnectionState _state = VoiceConnectionState.idle;
  List<VoiceTranscriptEntry> _lines = const [];
  String? _error;
  bool _permissionDenied = false;
  bool _muted = false;
  final _level = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(
      _voice.getConnectionState().listen((s) {
        if (!mounted) return;
        setState(() => _state = s);
        if (s == VoiceConnectionState.disconnected) HapticFeedback.lightImpact();
      }),
    );
    _subs.add(
      _voice.getTranscriptStream().listen((l) {
        if (!mounted) return;
        setState(() => _lines = l);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        });
      }),
    );
    _subs.add(_voice.levelStream.listen((v) => _level.value = v));
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _permissionDenied = false;
    });
    try {
      final biz = ref.read(businessProvider).value;
      await _voice.startTestSession(agentVariables: {'business_name': biz?.name ?? '', 'mode': 'owner_test'});
    } on VoiceAgentException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _permissionDenied = e.permissionDenied;
          _state = VoiceConnectionState.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "${ref.read(employeeNameProvider)} couldn't connect. ($e). Check your connection and try again.";
          _state = VoiceConnectionState.error;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive || s == AppLifecycleState.hidden) {
      if (_state != VoiceConnectionState.idle && _state != VoiceConnectionState.disconnected) {
        _voice.stopSession();
      }
    }
  }

  Future<void> _end() async {
    HapticFeedback.mediumImpact();
    await _voice.stopSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _voice.stopSession();
    _scroll.dispose();
    _level.dispose();
    super.dispose();
  }

  MascotState get _mascot => switch (_state) {
    VoiceConnectionState.speaking => MascotState.speaking,
    VoiceConnectionState.listening => MascotState.listening,
    VoiceConnectionState.thinking => MascotState.thinking,
    VoiceConnectionState.connecting => MascotState.calling,
    VoiceConnectionState.error => MascotState.error,
    VoiceConnectionState.disconnected => MascotState.success,
    VoiceConnectionState.idle => MascotState.welcome,
  };

  (String, Color) get _status => switch (_state) {
    VoiceConnectionState.connecting => ('Connecting…', AppColors.warm),
    VoiceConnectionState.listening => (_muted ? 'Muted' : 'Listening', AppColors.success),
    VoiceConnectionState.speaking => ('Speaking', AppColors.brand),
    VoiceConnectionState.thinking => ('Thinking…', AppColors.warm),
    VoiceConnectionState.disconnected => ('Disconnected', AppColors.cold),
    VoiceConnectionState.error => ('Couldn\'t connect', AppColors.hot),
    VoiceConnectionState.idle => ('Ready', AppColors.cold),
  };

  bool get _live => const {
    VoiceConnectionState.listening,
    VoiceConnectionState.speaking,
    VoiceConnectionState.thinking,
    VoiceConnectionState.connecting,
  }.contains(_state);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    final (label, color) = _status;
    final ended = _state == VoiceConnectionState.disconnected;

    return PopScope(
      onPopInvokedWithResult: (_, __) => _voice.stopSession(),
      child: Scaffold(
        appBar: AppBar(title: Text('Talk to $name')),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 4),
              Mascot(state: _mascot, size: MediaQuery.sizeOf(context).height < 700 ? 150 : 200),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: StatusDot(label: label, color: color, pulse: _live),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ValueListenableBuilder<double>(
                  valueListenable: _level,
                  builder: (_, v, __) =>
                      _Waveform(level: _live ? v : 0, color: _state == VoiceConnectionState.speaking ? AppColors.brand : AppColors.success),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: AppShadows.card,
                  ),
                  child: _error != null
                      ? _ErrorPanel(message: _error!, permissionDenied: _permissionDenied, onRetry: _start)
                      : _lines.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _state == VoiceConnectionState.connecting
                                  ? 'Connecting to $name…'
                                  : 'Say “Hello” to start. ${ref.watch(workflowProvider).testCallerHint}',
                              style: t.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          children: [
                            for (final l in _lines)
                              TranscriptBubble(isAgent: l.isAgent, text: l.text, who: l.isAgent ? name : 'You', pending: !l.isFinal),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, 16, AppSpace.page, 12),
                child: ended
                    ? Column(
                        children: [
                          Text('That\'s how $name handles your leads ✨', style: t.titleSmall),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SecondaryButton(label: 'Talk again', icon: Icons.replay_rounded, onPressed: _start),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PrimaryButton(
                                  label: widget.fromOnboarding ? 'Continue' : 'Done',
                                  color: AppColors.success,
                                  onPressed: () async {
                                    if (widget.fromOnboarding) {
                                      await ref.read(localPrefsProvider).setAgentTested(true);
                                      await ref.read(localPrefsProvider).setOnboarded(true);
                                      await ref.read(notificationServiceProvider).requestPermission();
                                      if (context.mounted) context.go('/home');
                                    } else {
                                      context.pop();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _RoundControl(
                            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            label: _muted ? 'Unmute' : 'Mute',
                            background: _muted ? AppColors.ink : Colors.white,
                            foreground: _muted ? Colors.white : AppColors.ink,
                            onTap: _live
                                ? () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _muted = !_muted);
                                    _voice.setMuted(_muted);
                                  }
                                : null,
                          ),
                          const SizedBox(width: 36),
                          _RoundControl(
                            icon: Icons.call_end_rounded,
                            label: 'End',
                            background: AppColors.hot,
                            foreground: Colors.white,
                            size: 76,
                            onTap: _live ? _end : (_error != null ? () => context.pop() : null),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
    this.size = 64,
  });
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: foreground, size: size * 0.42),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
      ],
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.permissionDenied, required this.onRetry});
  final String message;
  final bool permissionDenied;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: t.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: permissionDenied
                  ? PrimaryButton(label: 'Open settings', onPressed: openAppSettings)
                  : PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight animated bars driven by audio level.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.level, required this.color});
  final double level;
  final Color color;
  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: const Size(220, 44),
            painter: _WavePainter(phase: _c.value, level: widget.level, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.phase, required this.level, required this.color});
  final double phase;
  final double level;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const bars = 21;
    final w = size.width / (bars * 1.8);
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final center = 1 - ((i - bars / 2).abs() / (bars / 2));
      final wave = (math.sin((phase * 2 * math.pi) + i * 0.7) + 1) / 2;
      final h = 4 + (size.height - 8) * (0.08 + level * (0.35 + 0.65 * wave) * (0.4 + 0.6 * center));
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.phase != phase || o.level != level || o.color != color;
}

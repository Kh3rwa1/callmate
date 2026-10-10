import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_agent_service.dart';
import '../calls/transcript_view.dart';
import 'voice_test_composer.dart';
import 'voice_test_status.dart';
import 'voice_test_widgets.dart';

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

class _VoiceTestScreenState extends ConsumerState<VoiceTestScreen>
    with WidgetsBindingObserver {
  late final VoiceAgentService _voice = ref.read(voiceAgentServiceProvider);
  final _subs = <StreamSubscription<dynamic>>[];
  final _scroll = ScrollController();
  VoiceConnectionState _state = VoiceConnectionState.idle;
  List<VoiceTranscriptEntry> _lines = const [];
  String? _error;
  bool _permissionDenied = false;
  bool _muted = false;
  final _level = ValueNotifier<double>(0);
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(
      _voice.getConnectionState().listen((s) {
        if (!mounted) return;
        setState(() => _state = s);
        if (s == VoiceConnectionState.disconnected) Haptics.press();
      }),
    );
    _subs.add(
      _voice.getTranscriptStream().listen((l) {
        if (!mounted) return;
        setState(() => _lines = l);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }),
    );
    _subs.add(_voice.levelStream.listen((v) => _level.value = v));
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final strings = context.s;
    setState(() {
      _error = null;
      _permissionDenied = false;
    });
    try {
      final biz = ref.read(businessProvider).value;
      final name = ref.read(employeeNameProvider);
      await _voice.startTestSession(
        agentVariables: {
          'business_name': biz?.name ?? '',
          'agent_name': name,
          'gender': 'female',
          'voice': 'female',
          'speaker': 'meera',
          'tts_model': 'bulbul:v4-flash',
          'mode': 'owner_test',
        },
      );
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
          _error = strings.couldntConnectName(ref.read(employeeNameProvider));
          _state = VoiceConnectionState.error;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused ||
        s == AppLifecycleState.inactive ||
        s == AppLifecycleState.hidden) {
      if (_state != VoiceConnectionState.idle &&
          _state != VoiceConnectionState.disconnected) {
        _voice.stopSession();
      }
    }
  }

  Future<void> _end() async {
    Haptics.success();
    await _voice.stopSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _voice.stopSession();
    _inputController.dispose();
    _scroll.dispose();
    _level.dispose();
    super.dispose();
  }

  void _sendUserInput([String? overrideText]) {
    final text = (overrideText ?? _inputController.text).trim();
    if (text.isEmpty) return;
    _inputController.clear();
    Haptics.press();
    _voice.sendText(text);
  }

  void _toggleMute() {
    Haptics.tap();
    setState(() => _muted = !_muted);
    _voice.setMuted(_muted);
  }

  /// Leaves the screen. From onboarding this marks the agent as tested and
  /// onboarding as complete before going home.
  Future<void> _finish({bool requestNotifications = false}) async {
    if (!widget.fromOnboarding) {
      context.pop();
      return;
    }
    final prefs = ref.read(localPrefsProvider);
    await prefs.setAgentTested(true);
    await prefs.setOnboarded(true);
    if (requestNotifications) {
      await ref.read(notificationServiceProvider).requestPermission();
    }
    if (mounted) context.go('/home');
  }

  bool get _live => isLiveVoiceState(_state);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final name = ref.watch(employeeNameProvider);
    final (label, color) = voiceStatusFor(_state, muted: _muted, s: s);
    final ended = _state == VoiceConnectionState.disconnected;
    // With the keyboard up there is no room for the big mascot: it folds
    // away so the transcript and composer never overflow.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final mascotSize = MediaQuery.sizeOf(context).height < 700 ? 96.0 : 124.0;

    return PopScope(
      onPopInvokedWithResult: (_, _) => _voice.stopSession(),
      child: Scaffold(
        appBar: AppBar(title: Text(s.talkTo(name))),
        body: SafeArea(
          child: Column(
            children: [
              AnimatedSize(
                duration: AppMotion.of(context, AppMotion.base),
                curve: AppMotion.standard,
                child: keyboard
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        children: [
                          Mascot(
                            state: mascotForVoiceState(_state),
                            size: mascotSize,
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
              ),
              Semantics(
                liveRegion: true,
                child: SwapFade(
                  child: StatusDot(
                    key: ValueKey(label),
                    label: label,
                    color: color,
                    pulse: _live,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 36,
                child: ValueListenableBuilder<double>(
                  valueListenable: _level,
                  builder: (_, v, _) => VoiceWaveform(
                    level: _live ? v : 0,
                    color: _state == VoiceConnectionState.speaking
                        ? AppColors.brand
                        : AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.page),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.hairline, width: 0.8),
                    boxShadow: AppShadows.card,
                  ),
                  child: _buildTranscript(context, name),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  16,
                  AppSpace.page,
                  12,
                ),
                child: SwapFade(
                  child: KeyedSubtree(
                    key: ValueKey(ended),
                    child: ended
                        ? _buildEndedActions()
                        : _buildLiveControls(name),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscript(BuildContext context, String name) {
    if (_error != null) {
      return VoiceErrorPanel(
        message: _error!,
        permissionDenied: _permissionDenied,
        onRetry: _start,
        fromOnboarding: widget.fromOnboarding,
        onContinue: _finish,
      );
    }
    final s = context.s;
    if (_lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SwapFade(
            child: Text(
              _state == VoiceConnectionState.connecting
                  ? s.connectingTo(name)
                  : s.sayHello,
              key: ValueKey(_state == VoiceConnectionState.connecting),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.inkFaint),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final thinking = _state == VoiceConnectionState.thinking;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      children: [
        for (final (i, l) in _lines.indexed)
          TranscriptBubble(
            key: ValueKey('line-$i-${l.isAgent}'),
            isAgent: l.isAgent,
            text: l.text,
            who: l.isAgent ? name : s.you,
            pending: !l.isFinal,
            animate: true,
          ),
        AnimatedSize(
          duration: AppMotion.of(context, AppMotion.base),
          alignment: Alignment.topLeft,
          child: thinking
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(34, 6, 0, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: TypingDots(color: AppColors.brand, size: 6),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildEndedActions() {
    final s = context.s;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: s.talkAgain,
                icon: Icons.replay_rounded,
                onPressed: _start,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton(
                label: widget.fromOnboarding ? s.continueLabel : s.done,
                onPressed: () => _finish(requestNotifications: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveControls(String name) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: AppMotion.of(context, AppMotion.base),
          curve: AppMotion.standard,
          child: _live
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: VoiceTestComposer(
                    controller: _inputController,
                    employeeName: name,
                    onSend: _sendUserInput,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VoiceRoundControl(
              icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: _muted ? s.unmute : s.mute,
              background: _muted ? AppColors.inverse : AppColors.surface,
              foreground: _muted ? AppColors.onInverse : AppColors.ink,
              bordered: !_muted,
              onTap: _live ? _toggleMute : null,
            ),
            const SizedBox(width: 36),
            VoiceRoundControl(
              icon: Icons.call_end_rounded,
              label: s.end,
              background: AppColors.hotFill,
              foreground: Colors.white,
              size: 76,
              // Always available: ends a live call, or leaves when there is
              // nothing to end (failed or not started yet).
              onTap: _live ? _end : () => context.pop(),
            ),
          ],
        ),
      ],
    );
  }
}

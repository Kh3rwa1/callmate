import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_agent_service.dart';

/// Pure presentation mapping for the voice test screen, kept separate from the
/// widget so it can be unit tested.

/// Mascot pose for a given connection state.
MascotState mascotForVoiceState(VoiceConnectionState state) => switch (state) {
  VoiceConnectionState.speaking => MascotState.speaking,
  VoiceConnectionState.listening => MascotState.listening,
  VoiceConnectionState.thinking => MascotState.thinking,
  VoiceConnectionState.connecting => MascotState.calling,
  VoiceConnectionState.error => MascotState.error,
  VoiceConnectionState.disconnected => MascotState.success,
  VoiceConnectionState.idle => MascotState.welcome,
};

/// Status label and colour for a given connection state.
(String, Color) voiceStatusFor(
  VoiceConnectionState state, {
  bool muted = false,
  S s = S.en,
}) => switch (state) {
  VoiceConnectionState.connecting => (s.vConnecting, AppColors.warmInk),
  VoiceConnectionState.listening => (
    muted ? s.vMuted : s.vListening,
    AppColors.success,
  ),
  VoiceConnectionState.speaking => (s.vSpeaking, AppColors.brand),
  VoiceConnectionState.thinking => (s.vThinking, AppColors.warmInk),
  VoiceConnectionState.disconnected => (s.vDisconnected, AppColors.cold),
  VoiceConnectionState.error => (s.vCouldntConnect, AppColors.hot),
  VoiceConnectionState.idle => (s.vReady, AppColors.cold),
};

/// Whether a session is active (or being established) in [state].
bool isLiveVoiceState(VoiceConnectionState state) => const {
  VoiceConnectionState.listening,
  VoiceConnectionState.speaking,
  VoiceConnectionState.thinking,
  VoiceConnectionState.connecting,
}.contains(state);

/// Canned questions offered as chips: (chip label, message sent).
List<(String, String)> voiceTestSuggestions([S s = S.en]) => s.voiceSuggestions;

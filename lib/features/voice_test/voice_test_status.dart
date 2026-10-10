import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/employee_avatar.dart';
import '../../core/widgets/mascot.dart';
import '../../l10n/l10n.dart';
import '../../services/voice/voice_agent_service.dart';

/// Pure presentation mapping for the voice test screen, kept separate from the
/// widget so it can be unit tested.

/// Drawn mascot pose for a given connection state.
BirdPose mascotForVoiceState(VoiceConnectionState state) => switch (state) {
  VoiceConnectionState.speaking => BirdPose.speaking,
  VoiceConnectionState.listening => BirdPose.listening,
  VoiceConnectionState.thinking => BirdPose.thinking,
  VoiceConnectionState.connecting => BirdPose.calling,
  VoiceConnectionState.error => BirdPose.error,
  VoiceConnectionState.disconnected => BirdPose.success,
  VoiceConnectionState.idle => BirdPose.welcome,
};

/// What the employee's avatar shows for a given connection state.
EmployeeActivity employeeActivityFor(VoiceConnectionState state) =>
    switch (state) {
      VoiceConnectionState.speaking => EmployeeActivity.speaking,
      VoiceConnectionState.listening => EmployeeActivity.listening,
      VoiceConnectionState.thinking => EmployeeActivity.thinking,
      VoiceConnectionState.connecting => EmployeeActivity.calling,
      _ => EmployeeActivity.idle,
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
